package gui

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"yamp/internal/yam"
)

func testCache(t *testing.T) *trackCache {
	t.Helper()
	CacheDir = t.TempDir()
	c, err := newTrackCache()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		c.close()
		CacheDir = ""
	})
	return c
}

func putCached(t *testing.T, c *trackCache, id, codec string, size int64, auto bool, played time.Time) cacheEntry {
	t.Helper()
	path := filepath.Join(c.dir, id+cacheExt(codec))
	if err := os.WriteFile(path, make([]byte, size), 0o644); err != nil {
		t.Fatal(err)
	}
	e := cacheEntry{
		ID: id, Codec: codec, Quality: string(yam.MP3), Path: path,
		Size: size, Auto: auto, Created: played, Played: played,
	}
	if err := c.insert(e); err != nil {
		t.Fatal(err)
	}
	return e
}

func TestCacheDB(t *testing.T) {
	c := testCache(t)
	old := time.Now().Add(-2 * time.Hour)
	putCached(t, c, "t1", "mp3", 100, false, old)
	putCached(t, c, "t2", "flac-mp4", 200, true, old.Add(time.Hour))
	putCached(t, c, "t3", "aac", 50, true, time.Now())

	if !c.has("t1") || !c.has("t2") || c.has("t9") {
		t.Fatal("has: неверные ответы")
	}
	if e, ok := c.lookup("t2"); !ok || e.Size != 200 || !e.Auto || filepath.Ext(e.Path) != ".m4a" {
		t.Fatalf("lookup t2: %+v %v", e, ok)
	}
	if got := c.cachedIDs([]string{"t1", "t2", "t9"}); len(got) != 2 || !got["t1"] || !got["t2"] {
		t.Fatalf("cachedIDs: %v", got)
	}
	if used, count := c.stats(); used != 350 || count != 3 {
		t.Fatalf("stats: %d %d", used, count)
	}
	if plays := c.bumpPlay("t1"); plays != 1 {
		t.Fatalf("bumpPlay: %d", plays)
	}
	if plays := c.bumpPlay("t1"); plays != 2 {
		t.Fatalf("bumpPlay второй: %d", plays)
	}

	if n := c.autoSince(time.Now().Truncate(24 * time.Hour)); n != 2 {
		t.Fatalf("autoSince сегодня: %d", n)
	}
	if n := c.autoSince(old.Add(-time.Hour)); n != 2 {
		t.Fatalf("autoSince за всё время: %d", n)
	}

	c.enforce(300, "t3")
	if c.has("t2") {
		t.Fatal("t2 не вытеснен, хотя самый старый")
	}
	if !c.has("t1") || !c.has("t3") {
		t.Fatal("вытеснение задело свежие треки")
	}
	if used, _ := c.stats(); used != 150 {
		t.Fatalf("после вытеснения used: %d", used)
	}

	c.enforce(10, "t3")
	if !c.has("t3") {
		t.Fatal("текущий трек вытеснили")
	}
	if c.has("t2") {
		t.Fatal("t2 не вытеснен под жёсткий лимит")
	}

	c.remove("t3")
	if c.has("t3") {
		t.Fatal("remove не удалил запись")
	}
	if _, err := os.Stat(filepath.Join(c.dir, "t3.aac")); !os.IsNotExist(err) {
		t.Fatal("remove не удалил файл")
	}

	putCached(t, c, "t4", "mp3", 10, false, time.Now())
	putCached(t, c, "t5", "mp3", 10, false, time.Now())
	c.clear()
	if used, count := c.stats(); used != 0 || count != 0 {
		t.Fatalf("clear: %d %d", used, count)
	}
	entries, _ := os.ReadDir(c.dir)
	if len(entries) != 0 {
		t.Fatalf("после clear остались файлы: %d", len(entries))
	}
}

func TestCacheBrokenFile(t *testing.T) {
	c := testCache(t)
	e := putCached(t, c, "t1", "mp3", 100, false, time.Now())
	if err := os.Truncate(e.Path, 10); err != nil {
		t.Fatal(err)
	}
	if c.has("t1") {
		t.Fatal("битый файл посчитался кешем")
	}
}

func TestCacheServe(t *testing.T) {
	c := testCache(t)
	e := putCached(t, c, "t1", "mp3", 1000, false, time.Now())
	if err := os.WriteFile(e.Path, []byte(makeRange(1000)), 0o644); err != nil {
		t.Fatal(err)
	}
	s := newStreamServer()
	s.cache = c

	full := httptest.NewRecorder()
	s.serve(full, httptest.NewRequest(http.MethodGet, "/t1?q=lossless", nil))
	if full.Code != http.StatusOK || full.Body.Len() != 1000 {
		t.Fatalf("полный ответ: %d %d", full.Code, full.Body.Len())
	}
	if ct := full.Header().Get("Content-Type"); ct != "audio/mpeg" {
		t.Fatalf("Content-Type: %q", ct)
	}

	rng := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/t1", nil)
	req.Header.Set("Range", "bytes=100-199")
	s.serve(rng, req)
	if rng.Code != http.StatusPartialContent || rng.Body.Len() != 100 {
		t.Fatalf("диапазон: %d %d", rng.Code, rng.Body.Len())
	}
	if rng.Body.String() != makeRange(1000)[100:200] {
		t.Fatal("тело диапазона неверное")
	}

	head := httptest.NewRecorder()
	s.serve(head, httptest.NewRequest(http.MethodHead, "/t1", nil))
	if head.Code != http.StatusOK || head.Body.Len() != 0 {
		t.Fatalf("HEAD: %d %d", head.Code, head.Body.Len())
	}

	miss := httptest.NewRecorder()
	s.serve(miss, httptest.NewRequest(http.MethodGet, "/t9", nil))
	if miss.Code != http.StatusUnauthorized && miss.Code != http.StatusBadGateway {
		t.Fatalf("промах должен уйти в стример: %d", miss.Code)
	}
}

func makeRange(n int) string {
	s := make([]byte, n)
	for i := range s {
		s[i] = byte(i % 251)
	}
	return string(s)
}

func TestCacheConfig(t *testing.T) {
	c := defaultConfig()
	if !c.cacheOn() || c.cacheLimitMB() != defaultCacheLimitMB {
		t.Fatalf("умолчания: on=%v mb=%d", c.cacheOn(), c.cacheLimitMB())
	}
	if q := c.cachePlayQuality(); q != yam.MP3 {
		t.Fatalf("качество кеша по умолчанию: %v", q)
	}
	if m := c.cacheAutoMode(); m != cacheAutoOff {
		t.Fatalf("автокеш по умолчанию: %v", m)
	}

	c.CacheQuality = "lossless"
	if q := c.cachePlayQuality(); q != yam.MP3 {
		t.Fatalf("недопустимое качество кеша принято: %v", q)
	}
	c.CacheAuto = "всегда"
	if m := c.cacheAutoMode(); m != cacheAutoOff {
		t.Fatalf("недопустимый режим принят: %v", m)
	}
	v := -5
	c.CacheLimitMB = &v
	if c.cacheLimitMB() != 0 || c.cacheOn() {
		t.Fatal("отрицательный лимит не выключил кеш")
	}
	v = maxCacheLimitMB + 1
	if c.cacheLimitMB() != maxCacheLimitMB {
		t.Fatal("лимит не ограничен сверху")
	}
}

func TestCachePrefsRoundTrip(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(dir, "cfg"))
	t.Setenv("HOME", dir)
	c := defaultConfig()
	v := 512
	c.CacheLimitMB = &v
	c.CacheAuto = cacheAutoWifi
	c.CacheQuality = string(yam.Low)
	if err := c.save(); err != nil {
		t.Fatal(err)
	}
	loaded := loadConfig()
	if loaded.cacheLimitMB() != 512 || loaded.cacheAutoMode() != cacheAutoWifi || loaded.cachePlayQuality() != yam.Low {
		t.Fatalf("не восстановилось: %+v", loaded)
	}
}

func TestCacheCommands(t *testing.T) {
	dir := t.TempDir()
	for _, v := range []string{"AppData", "HOME", "XDG_CONFIG_HOME", "YAMP_CACHE", "LocalAppData"} {
		t.Setenv(v, dir)
	}
	events := make(chan map[string]any, 64)
	core := Start(func(event []byte) {
		var e map[string]any
		if err := json.Unmarshal(event, &e); err != nil {
			t.Errorf("событие не JSON: %q", event)
			return
		}
		events <- e
	})
	wait := func(want string) map[string]any {
		t.Helper()
		for {
			select {
			case e := <-events:
				if e["type"] == want {
					return e
				}
			case <-time.After(5 * time.Second):
				t.Fatalf("не дождались события %q", want)
				return nil
			}
		}
	}

	core.Send([]byte(`{"cmd":"prefs","cacheLimitMB":10,"cacheAuto":"wifi","cacheQuality":"low"}`))
	e := wait("state")
	if e["cacheLimitMB"] != float64(10) || e["cacheAuto"] != "wifi" || e["cacheQuality"] != "low" {
		t.Fatalf("настройки кеша в state: %v", e)
	}

	core.Send([]byte(`{"cmd":"cacheClear"}`))
	wait("cache")
	if e := wait("notice"); e["message"] != "Кеш очищен" {
		t.Fatalf("notice: %v", e)
	}

	core.Send([]byte(`{"cmd":"cacheAdd","track":"12345"}`))
	wait("notice")
	if e := wait("notice"); e["message"] != "Войдите в аккаунт, чтобы сохранять треки для офлайна" {
		t.Fatalf("notice без сессии: %v", e)
	}

	core.Send([]byte(`{"cmd":"prefs","cacheLimitMB":0}`))
	e = wait("state")
	if e["cacheOn"] != false {
		t.Fatalf("кеш не выключился: %v", e["cacheOn"])
	}
	core.Send([]byte(`{"cmd":"cacheAdd","track":"12345"}`))
	if e := wait("notice"); e["message"] != "Кеш выключен. Включите его в настройках, раздел «Кеш для офлайна»" {
		t.Fatalf("notice при выключенном кеше: %v", e)
	}

	core.Close()
	wait("exit")
}
