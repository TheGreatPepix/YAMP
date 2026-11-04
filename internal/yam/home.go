package yam

import (
	"context"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

const ChartLink = "chart"

func (c *Client) PersonalPlaylists(ctx context.Context) ([]Hit, error) {
	var feed struct {
		GeneratedPlaylists []struct {
			Type  string             `json:"type"`
			Ready bool               `json:"ready"`
			Data  *apiSearchPlaylist `json:"data"`
		} `json:"generatedPlaylists"`
	}
	if err := c.api(ctx, http.MethodGet, "/feed", nil, &feed); err != nil {
		return nil, err
	}
	var out []Hit
	for _, g := range feed.GeneratedPlaylists {
		if !g.Ready || g.Data == nil {
			continue
		}
		if h := playlistHit(*g.Data); h.Link != "" {
			out = append(out, h)
		}
	}
	return out, nil
}

func (c *Client) NewReleases(ctx context.Context, limit int) ([]Hit, error) {
	var list struct {
		NewReleases []flexID `json:"newReleases"`
	}
	if err := c.api(ctx, http.MethodGet, "/landing3/new-releases", nil, &list); err != nil {
		return nil, err
	}
	ids := make([]string, 0, limit)
	for _, id := range list.NewReleases {
		if len(ids) == limit {
			break
		}
		if id != "" {
			ids = append(ids, string(id))
		}
	}
	if len(ids) == 0 {
		return nil, nil
	}
	var albums []apiAlbum
	form := url.Values{"album-ids": {strings.Join(ids, ",")}}
	if err := c.api(ctx, http.MethodPost, "/albums", form, &albums); err != nil {
		return nil, err
	}
	var out []Hit
	for _, a := range albums {
		if h := albumHit(a); h.Link != "" {
			out = append(out, h)
		}
	}
	return out, nil
}

func (c *Client) NewPlaylists(ctx context.Context, limit int) ([]Hit, error) {
	var list struct {
		NewPlaylists []struct {
			UID  flexID `json:"uid"`
			Kind flexID `json:"kind"`
		} `json:"newPlaylists"`
	}
	if err := c.api(ctx, http.MethodGet, "/landing3/new-playlists", nil, &list); err != nil {
		return nil, err
	}
	ids := make([]string, 0, limit)
	for _, p := range list.NewPlaylists {
		if len(ids) == limit {
			break
		}
		if p.UID != "" && p.Kind != "" {
			ids = append(ids, string(p.UID)+":"+string(p.Kind))
		}
	}
	if len(ids) == 0 {
		return nil, nil
	}
	var playlists []apiSearchPlaylist
	form := url.Values{"playlist-ids": {strings.Join(ids, ",")}}
	if err := c.api(ctx, http.MethodPost, "/playlists/list", form, &playlists); err != nil {
		return nil, err
	}
	return playlistHits(playlists), nil
}

func (c *Client) History(ctx context.Context, limit int) ([]Hit, error) {
	var res struct {
		HistoryTabs []struct {
			Items []struct {
				Context struct {
					Type string `json:"type"`
					Data struct {
						FullModel struct {
							Album    *apiAlbum          `json:"album"`
							Artist   *apiSearchArtist   `json:"artist"`
							Playlist *apiSearchPlaylist `json:"playlist"`
						} `json:"fullModel"`
					} `json:"data"`
				} `json:"context"`
			} `json:"items"`
		} `json:"historyTabs"`
	}
	path := "/music-history?fullModelsCount=" + strconv.Itoa(limit*2)
	if err := c.api(ctx, http.MethodGet, path, nil, &res); err != nil {
		return nil, err
	}
	var out []Hit
	seen := map[string]bool{}
	for _, tab := range res.HistoryTabs {
		for _, it := range tab.Items {
			m := it.Context.Data.FullModel
			var h Hit
			switch it.Context.Type {
			case "album":
				if m.Album != nil {
					h = albumHit(*m.Album)
				}
			case "artist":
				if m.Artist != nil {
					h = artistHit(*m.Artist)
				}
			case "playlist":
				if m.Playlist != nil {
					h = playlistHit(*m.Playlist)
				}
			}
			if h.Link == "" || seen[h.Link] {
				continue
			}
			seen[h.Link] = true
			out = append(out, h)
			if len(out) == limit {
				return out, nil
			}
		}
	}
	return out, nil
}

func (c *Client) Chart(ctx context.Context) (*Release, error) {
	var res struct {
		Title string `json:"title"`
		Chart struct {
			Title  string `json:"title"`
			Tracks []struct {
				Track *apiTrack `json:"track"`
			} `json:"tracks"`
		} `json:"chart"`
	}
	if err := c.api(ctx, http.MethodGet, "/landing3/chart", nil, &res); err != nil {
		return nil, err
	}
	r := &Release{Kind: KindPlaylist, Title: "Чарт"}
	for _, it := range res.Chart.Tracks {
		if it.Track == nil {
			continue
		}
		if tr := it.Track.shape(nil); tr.ID != "" {
			r.Tracks = append(r.Tracks, tr)
		}
	}
	r.TrackCount = len(r.Tracks)
	return r, nil
}
