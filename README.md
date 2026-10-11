# Superstore Sales & Profitability Analytics

An end-to-end analysis of 9,994 retail order lines: raw CSV to a cleaned **SQL Server star schema**, **13 analysis queries** (CTEs and window functions), and a **3-page Power BI dashboard** with a DAX measure library.

**Core question:** where does the business lose money, and why?

![Executive Overview](images/01_overview.png)

## Key findings

| Finding | Evidence |
|---|---|
| Discounts above 20% destroy profit | Margin is **29.5%** with no discount, **11.9%** at 1-20%, then **-15.3%**, **-40.7%** and **-122.6%** in the 21-40%, 41-60% and over-60% bands |
| Deep discounts cost about 135K | Order lines discounted above 20% lose roughly 135,376 in total |
| Three sub-categories lose money overall | Tables (-17.7K), Bookcases (-3.5K), Supplies (-1.2K) |
| Losses are concentrated geographically | Texas (-25.7K), Ohio, Pennsylvania and Illinois account for about 70.9K of losses; the Central region has the weakest margin (7.9%) |
| Loss-making lines are a large share of orders | 1,871 lines (18.7%) lose a combined ~156K |
| Revenue is spread across the customer base | About half of customers (396 of 793) are needed to reach 80% of sales |

Overall: Sales 2,297,200.86, Profit 286,397.02, margin 12.47%, 5,009 orders, 793 customers.

## Tech stack

- **SQL Server 2025 Express** and SSMS: data loading, cleaning, star schema, analysis
- **Power BI Desktop**: data model, DAX, dashboard
- **Dataset:** [Superstore Dataset (Final) on Kaggle](https://www.kaggle.com/datasets/vivek468/superstore-dataset-final) by vivek468

## Data model

One fact table at order-line grain and five dimensions.

| Table | Rows | Contents |
|---|---|---|
| `fact_sales` | 9,994 | Keys, Sales, Quantity, Discount, Profit, Cost (derived) |
| `dim_date` | 1,826 | Calendar attributes, 2014 to 2018 |
| `dim_customer` | 793 | Customer ID, name, segment |
| `dim_product` | 1,894 | Product ID, name, category, sub-category |
| `dim_geography` | 632 | Country, region, state, city, postal code |
| `dim_ship_mode` | 4 | Ship mode |

`fact_sales[OrderDateKey]` is the active relationship to `dim_date`; `fact_sales[ShipDateKey]` is inactive and used with `USERELATIONSHIP`.

## Data quality issues found and fixed

- File is **Windows-1252** encoded with **LF** line endings: handled with `CODEPAGE = '1252'` and `ROWTERMINATOR = '0x0a'`.
- Dates are **US month/day/year text**: converted with style 101.
- **449 postal codes lost a leading zero** (New England and New Jersey): restored to five digits.
- **32 product IDs map to more than one product name**: product dimension keyed on ID plus name.
- Ship dates run into **January 2018**: date dimension extended to 2018.
- A hidden **carriage return** on the last column made `SUM(Profit)` return NULL: cleaned in staging.
- **1,871 negative-profit rows** were kept deliberately: they are real losses and drive the main finding.
- Loaded totals were reconciled to the source (9,994 rows, Sales 2,297,200.86, Profit 286,397.02).

## SQL highlights

`sql/02_analysis_queries.sql` contains 13 queries, including:

| Query | Technique |
|---|---|
| Year-over-year growth | `LAG` |
| Monthly trend with year-to-date total | `SUM() OVER`, `LAG(12)` |
| Sub-category profit ranking | `RANK` |
| Top and bottom 10 products | `ROW_NUMBER` |
| Discount-band margin analysis | `CASE` |
| RFM customer segmentation | `NTILE` |
| Pareto: customers needed for 80% of sales | cumulative `SUM() OVER` |
| Ship time by ship mode | `DATEDIFF` |

## Dashboard

| Page | Purpose |
|---|---|
| **Executive Overview** | KPI cards, sales trend, category sales, ten worst states by profit |
| **Profitability** | Sub-category and product profit, margin matrix, loss-makers in red |
| **Discount Impact** | Margin by discount band, loss cards, profit on discounts over 20% |

![Profitability](images/02_profitability.png)
![Discount Impact](images/03_discount_impact.png)

DAX measures are in `powerbi/04_dax_measures.dax` (KPIs, year-over-year, year-to-date, running total, loss and discount measures, average ship days).

## Repository structure

```
sql/        01_setup_import_star_schema.sql, 02_analysis_queries.sql, 03_create_views.sql
powerbi/    Superstore_Sales_Profitability.pbix, 04_dax_measures.dax, superstore_theme.json
images/     dashboard screenshots
docs/       Superstore_Project_Summary.docx
```

## How to reproduce

1. Download the CSV from Kaggle and save it as `C:\Data\Superstore.csv`.
2. In SSMS, connect to your SQL Server instance (for example `localhost\SQLEXPRESS`) and run `sql/01_setup_import_star_schema.sql` in sections. The final query should show 9,994 rows, Sales 2,297,200.86 and Profit 286,397.02.
3. Run `sql/02_analysis_queries.sql` to see the analysis.
4. Open the `.pbix` in Power BI Desktop and point the data source to your server and the `SuperstoreDB` database, or rebuild it by loading the six star-schema tables.

## Limitations

- The data is a well-known sample dataset, so results are descriptive and show associations, not proven causes. The discount effect is also mixed up with product mix (for example, some categories are discounted more often).
- `Cost` is derived as `Sales - Profit`, so it includes everything that reduces profit, not just cost of goods.
- Data covers orders from 2014 to 2017 only.

## Possible next steps

- Test whether discount level predicts losses after controlling for category (Python or statistics).
- Add an Excel pivot layer from `vw_sales_flat`.
- Add a customer-retention view built on the RFM segments.

## Dataset credit

Superstore Dataset (Final), Kaggle, by vivek468. Used for learning and portfolio purposes.
