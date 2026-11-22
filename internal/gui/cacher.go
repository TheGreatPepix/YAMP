package gui

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"yamp/internal/yam"
)

const (
	maxAutoPerDay   = 5
	autoCacheMargin = 4
	fullListen      = 0.85
)

type cacher struct {
	app   *App
	cache *trackCache
	gate  *gate

	mu      sync.Mutex
	busy    map[string]bool
	pending int
}

func newCacher(app *App, cache *trackCache) *cacher {
	return &cacher{app: app, cache: cache, gate: newGate(2), busy: map[string]bool{}}
}

func (g *App) emitCache() {
	if g.cache == nil {
		return
	}
	used, count := g.cache.stats()
	g.mu.Lock()
	limit := int64(0)
	if g.cfg.cacheOn() {
		limit = g.cfg.cacheLimitBytes()
	}
	g.mu.Unlock()
	g.emit(map[string]any{"type": "cache", "used": used, "limit": limit, "count": count})
}

func (g *App) cacheAdd(id string) {
	if id == "" {
		return
	}
	g.mu.Lock()
	q := g.cfg.cachePlayQuality()
	on := g.cfg.cacheOn()
	g.mu.Unlock()
	if !on {
		g.notice("Кеш выключен. Включите его в настройках, раздел «Кеш для офлайна»", "error")
		return
	}
	if g.cache.has(id) {
		g.notice("Трек уже сохранён для офлайна", "ok")
		return
	}
	meta, _ := g.findTrack(id)
	g.cacher.enqueue(id, meta, q, false)
	g.notice("Сохраняю для офлайна", "info")
}

const cacheLinkMax = 300

func (g *App) cacheLink(link string) {
	g.mu.Lock()
	q := g.cfg.cachePlayQuality()
	on := g.cfg.cacheOn()
	sess := g.session
	g.mu.Unlock()
	if link == "" {
		return
	}
	if !on {
		g.notice("Кеш выключен. Включите его в настройках, раздел «Кеш для офлайна»", "error")
		return
	}
	if sess == nil {
		g.notice("Войдите в аккаунт, чтобы сохранять треки для офлайна", "error")
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
		defer cancel()
		tracks, err := g.resolveForCache(ctx, sess, link)
		if err != nil {
			g.notice("Не удалось открыть: "+searchError(err), "error")
			return
		}
		if len(tracks) == 0 {
			g.notice("Здесь нет треков, которые можно сохранить", "error")
			return
		}
		if len(tracks) > cacheLinkMax {
			tracks = tracks[:cacheLinkMax]
		}
		n := g.cacher.enqueueAll(tracks, q)
		if n == 0 {
			g.notice("Уже всё сохранено для офлайна", "ok")
			return
		}
		g.notice("Сохраняю для офлайна: "+trackCountLabel(n), "info")
	}()
}

func (g *App) resolveForCache(ctx context.Context, sess *yam.Session, link string) ([]yam.Track, error) {
	switch link {
	case yam.LikedLink:
		rel, err := sess.ResolveLiked(ctx, sess.Account().UID)
		if err != nil {
			return nil, err
		}
		return rel.Tracks, nil
	case yam.ChartLink:
		rel, err := sess.Chart(ctx)
		if err != nil {
			return nil, err
		}
		return rel.Tracks, nil
	}
	l, err := yam.ParseLink(link)
	if err != nil {
		return nil, err
	}
	if l.Kind == yam.KindTrack {
		return sess.Tracks(ctx, []string{l.TrackID})
	}
	rel, err := sess.Resolve(ctx, l, true)
	if err != nil {
		return nil, err
	}
	return rel.Tracks, nil
}

func trackCountLabel(n int) string {
	mod10, mod100 := n%10, n%100
	word := "треков"
	switch {
	case mod10 == 1 && mod100 != 11:
		word = "трек"
	case mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14):
		word = "трека"
	}
	return fmt.Sprintf("%d %s", n, word)
}

func (g *App) findTrack(id string) (yam.Track, bool) {
	p := g.player
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, t := range p.queue.Tracks() {
		if t.ID == id {
			return t, true
		}
	}
	for _, l := range p.lists {
		for _, t := range l.Tracks {
			if t.ID == id {
				return t, true
			}
		}
	}
	return yam.Track{}, false
}

func (g *App) cacheRemove(id string) {
	if id == "" || g.cache == nil {
		return
	}
	g.cache.remove(id)
	g.cacheChanged()
}

func (g *App) cacheClear() {
	if g.cache == nil {
		return
	}
	g.cache.clear()
	g.cacheChanged()
	g.notice("Кеш очищен", "ok")
}

func (g *App) cacheChanged() {
	g.emitCache()
	g.emitPlayer("")
	g.emitQueue()
	p := g.player
	p.mu.Lock()
	_, open := p.lists[sourceCached]
	p.mu.Unlock()
	if open {
		g.openSource(sourceCached)
	}
}

func (c *cacher) enqueue(id string, meta yam.Track, q yam.Quality, auto bool) {
	c.mu.Lock()
	if c.busy[id] {
		c.mu.Unlock()
		return
	}
	c.busy[id] = true
	c.pending++
	c.mu.Unlock()

	ctx := context.Background()
	if err := c.gate.acquire(ctx); err != nil {
		c.done(id)
		return
	}
	go func() {
		defer c.gate.release()
		defer c.done(id)
		c.download(ctx, id, meta, q, auto)
	}()
}

func (c *cacher) enqueueAll(tracks []yam.Track, q yam.Quality) int {
	n := 0
	for _, t := range tracks {
		if !t.Available {
			continue
		}
		if c.cache.has(t.ID) {
			continue
		}
		c.mu.Lock()
		if c.busy[t.ID] {
			c.mu.Unlock()
			continue
		}
		c.mu.Unlock()
		c.enqueue(t.ID, t, q, false)
		n++
	}
	return n
}

func (c *cacher) done(id string) {
	var drained bool
	c.mu.Lock()
	delete(c.busy, id)
	c.pending--
	drained = c.pending <= 0
	c.mu.Unlock()
	if drained {
		c.enforceLimit()
	}
}

func (c *cacher) enforceLimit() {
	c.app.mu.Lock()
	limit := int64(0)
	if c.app.cfg.cacheOn() {
		limit = c.app.cfg.cacheLimitBytes()
	}
	c.app.mu.Unlock()
	if limit <= 0 {
		return
	}
	var current string
	if cur, ok := c.app.player.currentID(); ok {
		current = cur
	}
	c.cache.enforce(limit, current)
	c.app.cacheChanged()
}

func (c *cacher) download(ctx context.Context, id string, meta yam.Track, q yam.Quality, auto bool) {
	c.app.mu.Lock()
	sess := c.app.session
	c.app.mu.Unlock()
	if sess == nil {
		c.fail(id, auto, yam.ErrNoPlus)
		return
	}

	part := filepath.Join(c.cache.dir, id+".part")
	format, n, err := sess.StreamFile(ctx, id, q, part, nil)
	if err != nil {
		_ = os.Remove(part)
		c.fail(id, auto, err)
		return
	}
	final := filepath.Join(c.cache.dir, id+cacheExt(format.Codec))
	_ = os.Remove(final)
	if err := os.Rename(part, final); err != nil {
		_ = os.Remove(part)
		c.fail(id, auto, err)
		return
	}

	now := time.Now()
	if err := c.cache.insert(cacheEntry{
		ID: id, Codec: format.Codec, Quality: string(q), Path: final,
		Title: meta.Title, Artist: meta.Artists, Cover: meta.Cover, Duration: meta.Duration,
		Size: n, Bitrate: format.Bitrate, Auto: auto, Created: now, Played: now,
	}); err != nil {
		_ = os.Remove(final)
		c.fail(id, auto, err)
		return
	}
	c.app.cacheChanged()
}

func (c *cacher) fail(id string, auto bool, err error) {
	c.app.logf("Кеш %s: %v", id, err)
	if !auto {
		if errors.Is(err, yam.ErrNoPlus) || errors.Is(err, yam.ErrUnauthorized) {
			c.app.notice("Войдите в аккаунт, чтобы сохранять треки для офлайна", "error")
			return
		}
		c.app.notice("Не удалось сохранить трек для офлайна: "+searchError(err), "error")
	}
}

func (g *App) autoCache(t yam.Track) {
	if g.cache == nil || g.cacher == nil {
		return
	}
	g.mu.Lock()
	if !g.cfg.cacheOn() {
		g.mu.Unlock()
		return
	}
	mode := g.cfg.cacheAutoMode()
	q := g.cfg.cachePlayQuality()
	metered := g.metered
	limit := g.cfg.cacheLimitBytes()
	g.mu.Unlock()

	if mode == cacheAutoOff || (metered && mode != cacheAutoAlways) {
		return
	}
	dayStart := time.Now().Truncate(24 * time.Hour)
	if g.cache.autoSince(dayStart) >= maxAutoPerDay {
		return
	}
	used, _ := g.cache.stats()
	if used >= limit/autoCacheMargin*(autoCacheMargin-1) {
		return
	}
	g.cacher.enqueue(t.ID, t, q, true)
}
