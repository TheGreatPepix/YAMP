package gui

import (
	"crypto/rand"
	"encoding/hex"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"yamp/internal/yam"
)

type streamServer struct {
	streamer *yam.Streamer
	cache    *trackCache

	once sync.Once
	base string
	err  error
}

func newStreamServer() *streamServer {
	return &streamServer{streamer: yam.NewStreamer()}
}

func (s *streamServer) start() (string, error) {
	s.once.Do(func() {
		ln, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			s.err = err
			return
		}
		var b [16]byte
		_, _ = rand.Read(b[:])
		prefix := "/" + hex.EncodeToString(b[:])
		mux := http.NewServeMux()
		mux.Handle(prefix+"/", http.StripPrefix(prefix, http.HandlerFunc(s.serve)))
		srv := &http.Server{Handler: mux, ReadHeaderTimeout: 10 * time.Second}
		go func() { _ = srv.Serve(ln) }()
		s.base = "http://" + ln.Addr().String() + prefix
	})
	return s.base, s.err
}

func (s *streamServer) serve(w http.ResponseWriter, r *http.Request) {
	if s.cache != nil {
		id := strings.Trim(r.URL.Path, "/")
		if e, ok := s.cache.lookup(id); ok && serveCached(w, r, e) {
			return
		}
	}
	s.streamer.ServeHTTP(w, r)
}

func serveCached(w http.ResponseWriter, r *http.Request, e cacheEntry) bool {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		return false
	}
	f, err := os.Open(e.Path)
	if err != nil {
		return false
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		return false
	}
	h := w.Header()
	h.Set("Content-Type", yam.ContentType(e.Codec))
	h.Set("Accept-Ranges", "bytes")
	h.Set("Cache-Control", "no-store")
	http.ServeContent(w, r, "", st.ModTime(), f)
	return true
}

func (s *streamServer) url(trackID string, q yam.Quality) (string, error) {
	base, err := s.start()
	if err != nil {
		return "", err
	}
	return base + "/" + url.PathEscape(trackID) + "?q=" + url.QueryEscape(string(q)), nil
}
