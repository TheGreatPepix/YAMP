package gui

import (
	"database/sql"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	_ "modernc.org/sqlite"
)

var CacheDir string

type cacheEntry struct {
	ID       string
	Codec    string
	Path     string
	Quality  string
	Title    string
	Artist   string
	Cover    string
	Size     int64
	Bitrate  int
	Duration int
	Plays    int
	Auto     bool
	Created  time.Time
	Played   time.Time
}

type trackCache struct {
	mu  sync.Mutex
	db  *sql.DB
	dir string
}

func cacheRoot() string {
	if CacheDir != "" {
		return CacheDir
	}
	if dir := os.Getenv("YAMP_CACHE"); dir != "" {
		return dir
	}
	dir, err := os.UserCacheDir()
	if err != nil || dir == "" {
		dir = os.TempDir()
	}
	return filepath.Join(dir, "yamp")
}

func newTrackCache() (*trackCache, error) {
	root := cacheRoot()
	dir := filepath.Join(root, "cache")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite", filepath.Join(root, "cache.db"))
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	for _, q := range []string{
		"PRAGMA journal_mode = TRUNCATE",
		"PRAGMA busy_timeout = 5000",
		`CREATE TABLE IF NOT EXISTS tracks (
			id TEXT PRIMARY KEY,
			codec TEXT NOT NULL DEFAULT '',
			quality TEXT NOT NULL DEFAULT '',
			path TEXT NOT NULL,
			title TEXT NOT NULL DEFAULT '',
			artist TEXT NOT NULL DEFAULT '',
			cover TEXT NOT NULL DEFAULT '',
			size INTEGER NOT NULL DEFAULT 0,
			bitrate INTEGER NOT NULL DEFAULT 0,
			duration INTEGER NOT NULL DEFAULT 0,
			plays INTEGER NOT NULL DEFAULT 0,
			auto INTEGER NOT NULL DEFAULT 0,
			created INTEGER NOT NULL DEFAULT 0,
			played INTEGER NOT NULL DEFAULT 0
		)`,
	} {
		if _, err := db.Exec(q); err != nil {
			db.Close()
			return nil, err
		}
	}
	for _, column := range []string{
		"title TEXT NOT NULL DEFAULT ''",
		"artist TEXT NOT NULL DEFAULT ''",
		"cover TEXT NOT NULL DEFAULT ''",
		"duration INTEGER NOT NULL DEFAULT 0",
	} {
		_, _ = db.Exec(`ALTER TABLE tracks ADD COLUMN ` + column)
	}
	return &trackCache{db: db, dir: dir}, nil
}

func (c *trackCache) close() {
	c.mu.Lock()
	defer c.mu.Unlock()
	_ = c.db.Close()
}

const cacheColumns = `id, codec, quality, path, title, artist, cover, size, bitrate, duration, plays, auto, created, played`

type rowScanner interface {
	Scan(...any) error
}

func scanEntry(s rowScanner) (cacheEntry, error) {
	var e cacheEntry
	var created, played int64
	err := s.Scan(&e.ID, &e.Codec, &e.Quality, &e.Path, &e.Title, &e.Artist, &e.Cover, &e.Size, &e.Bitrate, &e.Duration, &e.Plays, &e.Auto, &created, &played)
	e.Created = time.Unix(created, 0)
	e.Played = time.Unix(played, 0)
	return e, err
}

func (c *trackCache) lookup(id string) (cacheEntry, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	e, err := scanEntry(c.db.QueryRow(`SELECT `+cacheColumns+` FROM tracks WHERE id = ?`, id))
	if err != nil {
		return cacheEntry{}, false
	}
	if st, err := os.Stat(e.Path); err != nil || st.Size() != e.Size {
		return cacheEntry{}, false
	}
	return e, true
}

func (c *trackCache) has(id string) bool {
	_, ok := c.lookup(id)
	return ok
}

func (c *trackCache) cachedIDs(ids []string) map[string]bool {
	out := map[string]bool{}
	if len(ids) == 0 {
		return out
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	marks := strings.Repeat("?,", len(ids)-1) + "?"
	rows, err := c.db.Query(`SELECT id FROM tracks WHERE id IN (`+marks+`)`, idsToAny(ids)...)
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			out[id] = true
		}
	}
	return out
}

func idsToAny(ids []string) []any {
	out := make([]any, len(ids))
	for i, id := range ids {
		out[i] = id
	}
	return out
}

func (c *trackCache) insert(e cacheEntry) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	_, err := c.db.Exec(
		`INSERT OR REPLACE INTO tracks (id, codec, quality, path, title, artist, cover, size, bitrate, duration, plays, auto, created, played)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		e.ID, e.Codec, e.Quality, e.Path, e.Title, e.Artist, e.Cover, e.Size, e.Bitrate, e.Duration, e.Plays, e.Auto, e.Created.Unix(), e.Played.Unix(),
	)
	return err
}

func (c *trackCache) remove(id string) {
	c.mu.Lock()
	var path string
	_ = c.db.QueryRow(`SELECT path FROM tracks WHERE id = ?`, id).Scan(&path)
	_, _ = c.db.Exec(`DELETE FROM tracks WHERE id = ?`, id)
	c.mu.Unlock()
	if path != "" {
		_ = os.Remove(path)
	}
}

func (c *trackCache) clear() {
	c.mu.Lock()
	var paths []string
	rows, err := c.db.Query(`SELECT path FROM tracks`)
	if err == nil {
		for rows.Next() {
			var p string
			if rows.Scan(&p) == nil {
				paths = append(paths, p)
			}
		}
		rows.Close()
	}
	_, _ = c.db.Exec(`DELETE FROM tracks`)
	c.mu.Unlock()
	for _, p := range paths {
		_ = os.Remove(p)
	}
}

func (c *trackCache) stats() (used int64, count int) {
	c.mu.Lock()
	defer c.mu.Unlock()
	_ = c.db.QueryRow(`SELECT COALESCE(SUM(size), 0), COUNT(*) FROM tracks`).Scan(&used, &count)
	return used, count
}

func (c *trackCache) bumpPlay(id string) int {
	c.mu.Lock()
	defer c.mu.Unlock()
	_, _ = c.db.Exec(`UPDATE tracks SET plays = plays + 1, played = ? WHERE id = ?`, time.Now().Unix(), id)
	var plays int
	_ = c.db.QueryRow(`SELECT plays FROM tracks WHERE id = ?`, id).Scan(&plays)
	return plays
}

func (c *trackCache) autoSince(t time.Time) int {
	c.mu.Lock()
	defer c.mu.Unlock()
	var n int
	_ = c.db.QueryRow(`SELECT COUNT(*) FROM tracks WHERE auto = 1 AND created >= ?`, t.Unix()).Scan(&n)
	return n
}

func (c *trackCache) oldest(exclude string) (cacheEntry, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	e, err := scanEntry(c.db.QueryRow(
		`SELECT `+cacheColumns+` FROM tracks WHERE id != ? ORDER BY played ASC, created ASC LIMIT 1`, exclude,
	))
	if err != nil {
		return cacheEntry{}, false
	}
	return e, true
}

func (c *trackCache) listAll() []cacheEntry {
	c.mu.Lock()
	defer c.mu.Unlock()
	rows, err := c.db.Query(`SELECT ` + cacheColumns + ` FROM tracks ORDER BY played DESC`)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []cacheEntry
	for rows.Next() {
		if e, err := scanEntry(rows); err == nil {
			if st, err := os.Stat(e.Path); err == nil && st.Size() == e.Size {
				out = append(out, e)
			}
		}
	}
	return out
}

func (c *trackCache) enforce(limit int64, exclude string) {
	for {
		used, _ := c.stats()
		if used <= limit {
			return
		}
		victim, ok := c.oldest(exclude)
		if !ok {
			return
		}
		c.remove(victim.ID)
	}
}

func cacheExt(codec string) string {
	switch strings.ToLower(codec) {
	case "flac":
		return ".flac"
	case "mp3":
		return ".mp3"
	case "aac", "he-aac":
		return ".aac"
	default:
		return ".m4a"
	}
}
