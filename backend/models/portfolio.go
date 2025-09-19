package models

type PortfolioItem struct {
	Symbol string  `json:"symbol"`
	Lots   int     `json:"lots"`
	Price  float64 `json:"price"`
}
