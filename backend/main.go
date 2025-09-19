package main

import (
	"encoding/json"
	"net/http"
	"sync"

	"github.com/OkyayBegum/portfolio-tracker/backend/models"
	"github.com/gorilla/mux"
)

var (
	portfolio []models.PortfolioItem
	mu        sync.Mutex
)

func main() {
	r := mux.NewRouter()

	r.HandleFunc("/api/portfolio", getPortfolio).Methods("GET")
	r.HandleFunc("/api/add", addItem).Methods("POST")
	r.HandleFunc("/api/update", updateItem).Methods("PUT")
	r.HandleFunc("/api/delete/{symbol}", deleteItem).Methods("DELETE")

	http.ListenAndServe(":8080", r)
}

func getPortfolio(w http.ResponseWriter, r *http.Request) {
	mu.Lock()
	defer mu.Unlock()
	json.NewEncoder(w).Encode(portfolio)
}

func addItem(w http.ResponseWriter, r *http.Request) {
	var item models.PortfolioItem
	if err := json.NewDecoder(r.Body).Decode(&item); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	mu.Lock()
	portfolio = append(portfolio, item)
	mu.Unlock()
	w.WriteHeader(http.StatusCreated)
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
			portfolio[i] = updated
			w.WriteHeader(http.StatusOK)
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
			portfolio = append(portfolio[:i], portfolio[i+1:]...)
			w.WriteHeader(http.StatusOK)
			return
		}
	}
	http.Error(w, "Symbol not found", http.StatusNotFound)
}
