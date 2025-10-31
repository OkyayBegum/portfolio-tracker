package main

import (
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/OkyayBegum/portfolio-tracker/backend/models"
	"github.com/gorilla/mux"
)

var (
	portfolio []models.PortfolioItem
	mu        sync.Mutex
)

const (
	dataDir      = "data"
	dataFileName = "portfolio.json"
)

func main() {
	// ensure data directory and file exist, then load existing portfolio
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		log.Fatalf("failed to create data dir: %v", err)
	}
	if err := loadPortfolioFromFile(); err != nil {
		log.Fatalf("failed to load portfolio: %v", err)
	}

	r := mux.NewRouter()

	r.HandleFunc("/api/portfolio", getPortfolio).Methods("GET")
	r.HandleFunc("/api/portfolio/total", getPortfolioTotal).Methods("GET")
	r.HandleFunc("/api/add", addItem).Methods("POST")
	r.HandleFunc("/api/update", updateItem).Methods("PUT")
	r.HandleFunc("/api/delete/{symbol}", deleteItem).Methods("DELETE")

	log.Println("listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", r))
}

func getPortfolio(w http.ResponseWriter, r *http.Request) {
	// Return portfolio but first try to refresh current prices from the 3rd-party API.
	// Strategy:
	// 1. copy current portfolio under lock
	// 2. refresh prices concurrently with bounded concurrency
	// 3. update in-memory portfolio and persist if prices changed
	mu.Lock()
	current := append([]models.PortfolioItem(nil), portfolio...)
	mu.Unlock()

	// concurrency limiter
	const maxConcurrent = 5
	sem := make(chan struct{}, maxConcurrent)
	var wg sync.WaitGroup
	updatedPrices := make([]float64, len(current))

	for i, it := range current {
		wg.Add(1)
		go func(idx int, item models.PortfolioItem) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			// Try to fetch current price; don't fail the whole request on individual errors
			if p, err := fetchCurrentPrice(item.Symbol); err == nil && p > 0 {
				updatedPrices[idx] = p
			} else {
				// keep zero to indicate no update; log for debugging
				log.Printf("price refresh failed for %s: %v", item.Symbol, err)
			}
		}(i, it)
	}
	wg.Wait()

	// Build response slice using updated prices when available, otherwise existing
	resp := make([]models.PortfolioItem, len(current))
	changed := false
	for i, it := range current {
		if updatedPrices[i] > 0 {
			resp[i] = models.PortfolioItem{Symbol: it.Symbol, Lots: it.Lots, Price: updatedPrices[i]}
			if updatedPrices[i] != it.Price {
				changed = true
			}
		} else {
			resp[i] = it
		}
	}

	// If any prices changed, persist the updated portfolio
	if changed {
		mu.Lock()
		// copy resp into global portfolio
		portfolio = append([]models.PortfolioItem(nil), resp...)
		if err := savePortfolioToFile(); err != nil {
			log.Printf("failed to persist refreshed prices: %v", err)
			// don't fail the response; continue to return the refreshed view
		}
		mu.Unlock()
	}

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(resp); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}

// getPortfolioTotal returns the total value of the portfolio (sum of lots * price)
func getPortfolioTotal(w http.ResponseWriter, r *http.Request) {
	mu.Lock()
	defer mu.Unlock()
	var total float64
	for _, item := range portfolio {
		total += float64(item.Lots) * item.Price
	}
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(map[string]float64{"total": total}); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}

func addItem(w http.ResponseWriter, r *http.Request) {
	// Expect payload: {"symbol":"ABC","lots":2}
	var payload struct {
		Symbol string `json:"symbol"`
		Lots   int    `json:"lots"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// fetch current price from Yahoo Finance
	price, err := fetchCurrentPrice(payload.Symbol)
	if err != nil {
		log.Printf("failed to fetch price for %s: %v", payload.Symbol, err)
		http.Error(w, fmt.Sprintf("failed to fetch price for %s", payload.Symbol), http.StatusBadGateway)
		return
	}

	// reject zero or negative prices as likely errors
	if price <= 0 {
		log.Printf("fetched non-positive price for %s: %v", payload.Symbol, price)
		http.Error(w, fmt.Sprintf("invalid price fetched for %s", payload.Symbol), http.StatusBadGateway)
		return
	}

	item := models.PortfolioItem{Symbol: payload.Symbol, Lots: payload.Lots, Price: price}

	mu.Lock()
	old := append([]models.PortfolioItem(nil), portfolio...)
	portfolio = append(portfolio, item)
	if err := savePortfolioToFile(); err != nil {
		// revert
		portfolio = old
		mu.Unlock()
		log.Printf("failed to save after add: %v", err)
		http.Error(w, "failed to persist item", http.StatusInternalServerError)
		return
	}
	mu.Unlock()
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(item)
}

// fetchCurrentPrice queries Yahoo Finance chart API using Go's http.Client
// with browser-like headers and simple retry/backoff to avoid 429.
func fetchCurrentPrice(symbol string) (float64, error) {
	// Yahoo sembolü: MAVI -> MAVI.IS
	s := symbol
	if !strings.Contains(s, ".") {
		s = s + ".IS"
	}

	// URL inşası (güvenli kaçış)
	base := "https://query1.finance.yahoo.com/v8/finance/chart/"
	u, err := url.Parse(base + url.PathEscape(s))
	if err != nil {
		return 0, fmt.Errorf("bad url: %w", err)
	}
	q := u.Query()
	q.Set("range", "1d")
	q.Set("interval", "1d")
	u.RawQuery = q.Encode()

	// HTTP client (timeout + keepalive defaultları yeterli)
	client := &http.Client{Timeout: 5 * time.Second}

	// Tarayıcı gibi görünmek için header’lar
	hdrUA := "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
		"(KHTML, like Gecko) Chrome/127.0.0.1 Safari/537.36"
	hdrAcc := "application/json,text/plain,*/*"

	// 429/5xx için exponential backoff (+ küçük jitter)
	const maxAttempts = 4
	for attempt := 0; attempt < maxAttempts; attempt++ {
		req, _ := http.NewRequest("GET", u.String(), nil)
		req.Header.Set("User-Agent", hdrUA)
		req.Header.Set("Accept", hdrAcc)
		req.Header.Set("Accept-Language", "en-US,en;q=0.9,tr;q=0.8")
		req.Header.Set("Referer", "https://finance.yahoo.com/")

		resp, err := client.Do(req)
		if err != nil {
			// network hatası → kısa bekleyip tekrar dene
			backoff(attempt)
			continue
		}

		// response body'yi kapatmayı unutmayalım
		func() {
			defer resp.Body.Close()

			if resp.StatusCode == http.StatusOK {
				var doc map[string]interface{}
				if err := json.NewDecoder(resp.Body).Decode(&doc); err != nil {
					// JSON parse hatası → bekleyip tekrar dene
					backoff(attempt)
					return
				}
				if p, err := extractPriceFromYahooJSON(doc); err == nil && p > 0 {
					price = p
					ok = true
				}
			}

			// 429, 403, 500–599 ise bekleyip tekrar dene
			if resp.StatusCode == http.StatusTooManyRequests ||
				resp.StatusCode == http.StatusForbidden ||
				(resp.StatusCode >= 500 && resp.StatusCode <= 599) {
				backoff(attempt)
				return
			}

			// Diğer tüm status’larda tekrarlamak pek anlamlı değil
			if !ok {
				errFinal = fmt.Errorf("upstream status %d from yahoo", resp.StatusCode)
			}
		}()

		if ok {
			return price, nil
		}
		if errFinal != nil {
			return 0, errFinal
		}
	}

	return 0, fmt.Errorf("could not fetch price for %s after %d attempts", symbol, maxAttempts)
}

var (
	errFinal error
	price    float64
	ok       bool
)

// tiny helper: exponential backoff with jitter (attempt: 0,1,2,3...)
func backoff(attempt int) {
	base := 200 * time.Millisecond
	d := time.Duration(1<<attempt) * base
	jitter := time.Duration(rand.Intn(200)) * time.Millisecond
	time.Sleep(d + jitter)
}

// extractPriceFromYahooJSON walks the Yahoo chart JSON and tries several locations
// for a sensible price: meta.regularMarketPrice, indicators.quote.close (last), meta.previousClose
func extractPriceFromYahooJSON(doc map[string]interface{}) (float64, error) {
	// chart -> result -> [0]
	chart, ok := doc["chart"].(map[string]interface{})
	if !ok {
		return 0, fmt.Errorf("no chart object")
	}
	results, ok := chart["result"].([]interface{})
	if !ok || len(results) == 0 {
		return 0, fmt.Errorf("no result array")
	}
	res0, ok := results[0].(map[string]interface{})
	if !ok {
		return 0, fmt.Errorf("unexpected result item")
	}

	// 1) meta.regularMarketPrice
	if meta, ok := res0["meta"].(map[string]interface{}); ok {
		if v, exists := meta["regularMarketPrice"]; exists {
			if p, err := toFloat64(v); err == nil && p > 0 {
				return p, nil
			}
		}
		// fallback to previousClose
		if v, exists := meta["previousClose"]; exists {
			if p, err := toFloat64(v); err == nil && p > 0 {
				return p, nil
			}
		}
	}

	// 2) indicators -> quote -> close (take last non-null)
	if indicators, ok := res0["indicators"].(map[string]interface{}); ok {
		if quotes, ok := indicators["quote"].([]interface{}); ok && len(quotes) > 0 {
			if q0, ok := quotes[0].(map[string]interface{}); ok {
				if closes, ok := q0["close"].([]interface{}); ok && len(closes) > 0 {
					// iterate backwards to find last non-nil close
					for i := len(closes) - 1; i >= 0; i-- {
						if closes[i] == nil {
							continue
						}
						if p, err := toFloat64(closes[i]); err == nil && p > 0 {
							return p, nil
						}
					}
				}
			}
		}
	}

	return 0, fmt.Errorf("no usable price found in response")
}

// toFloat64 converts json number types to float64
func toFloat64(v interface{}) (float64, error) {
	switch x := v.(type) {
	case float64:
		return x, nil
	case float32:
		return float64(x), nil
	case int:
		return float64(x), nil
	case int64:
		return float64(x), nil
	case string:
		var f float64
		if _, err := fmt.Sscanf(x, "%f", &f); err == nil {
			return f, nil
		}
		return 0, fmt.Errorf("cannot parse string to float: %s", x)
	case map[string]interface{}:
		// Yahoo sometimes returns an object like {"raw": 123.45, "fmt":"123.45"}
		if raw, ok := x["raw"]; ok {
			return toFloat64(raw)
		}
		return 0, fmt.Errorf("map does not contain raw field")
	default:
		return 0, fmt.Errorf("unsupported number type %T", v)
	}
}

func updateItem(w http.ResponseWriter, r *http.Request) {
	var updated models.PortfolioItem
	if err := json.NewDecoder(r.Body).Decode(&updated); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	mu.Lock()
	defer mu.Unlock()
	for i, item := range portfolio {
		if item.Symbol == updated.Symbol {
			// snapshot and attempt save
			oldItem := portfolio[i]
			portfolio[i] = updated
			if err := savePortfolioToFile(); err != nil {
				// revert
				portfolio[i] = oldItem
				log.Printf("failed to save after update: %v", err)
				http.Error(w, "failed to persist update", http.StatusInternalServerError)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(updated)
			return
		}
	}
	http.Error(w, "Symbol not found", http.StatusNotFound)
}

func deleteItem(w http.ResponseWriter, r *http.Request) {
	symbol := mux.Vars(r)["symbol"]
	mu.Lock()
	defer mu.Unlock()
	for i, item := range portfolio {
		if item.Symbol == symbol {
			// snapshot and attempt save
			removed := item
			portfolio = append(portfolio[:i], portfolio[i+1:]...)
			if err := savePortfolioToFile(); err != nil {
				// revert: insert removed back
				portfolio = append(portfolio[:i], append([]models.PortfolioItem{removed}, portfolio[i:]...)...)
				log.Printf("failed to save after delete: %v", err)
				http.Error(w, "failed to persist delete", http.StatusInternalServerError)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(map[string]string{"deleted": symbol})
			return
		}
	}
	http.Error(w, "Symbol not found", http.StatusNotFound)
}

// loadPortfolioFromFile loads the portfolio from the JSON file. If the file
// doesn't exist it creates an empty JSON array file.
func loadPortfolioFromFile() error {
	file := filepath.Join(dataDir, dataFileName)
	// if file doesn't exist, create empty array
	if _, err := os.Stat(file); os.IsNotExist(err) {
		if err := os.WriteFile(file, []byte("[]"), 0644); err != nil {
			return err
		}
		portfolio = []models.PortfolioItem{}
		return nil
	}
	// read and decode
	b, err := os.ReadFile(file)
	if err != nil {
		return err
	}
	var p []models.PortfolioItem
	if err := json.Unmarshal(b, &p); err != nil {
		return err
	}
	portfolio = p
	return nil
}

// savePortfolioToFile writes the in-memory portfolio to the JSON file safely.
func savePortfolioToFile() error {
	file := filepath.Join(dataDir, dataFileName)
	b, err := json.MarshalIndent(portfolio, "", "  ")
	if err != nil {
		return err
	}
	tmp := file + ".tmp"
	if err := os.WriteFile(tmp, b, 0644); err != nil {
		return err
	}
	return os.Rename(tmp, file)
}
