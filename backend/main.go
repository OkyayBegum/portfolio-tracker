package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sync"

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
	r.HandleFunc("/api/add", addItem).Methods("POST")
	r.HandleFunc("/api/update", updateItem).Methods("PUT")
	r.HandleFunc("/api/delete/{symbol}", deleteItem).Methods("DELETE")

	log.Println("listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", r))
}

func getPortfolio(w http.ResponseWriter, r *http.Request) {
	mu.Lock()
	defer mu.Unlock()
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(portfolio); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}

func addItem(w http.ResponseWriter, r *http.Request) {
	var item models.PortfolioItem
	if err := json.NewDecoder(r.Body).Decode(&item); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	mu.Lock()
	// keep snapshot to revert on failure
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
