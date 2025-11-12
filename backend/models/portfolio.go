package models

type PortfolioItem struct {
	Symbol string  `json:"symbol"`
	Lots   float64 `json:"lots"`
	Price  float64 `json:"price"`
}
