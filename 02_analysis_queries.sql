/* =====================================================================
   Superstore Sales & Profitability Project
   Script 02 - Business analysis queries (CTEs + window functions)
   Run AFTER script 01. Each query is independent: highlight one + F5.
   ===================================================================== */
USE SuperstoreDB;
GO

/* ---------------------------------------------------------------------
   Q1. HEADLINE KPIs
   --------------------------------------------------------------------- */
SELECT  CAST(SUM(Sales)  AS DECIMAL(14,2))                         AS TotalSales,
        CAST(SUM(Profit) AS DECIMAL(14,2))                         AS TotalProfit,
        CAST(100.0 * SUM(Profit) / SUM(Sales) AS DECIMAL(5,2))     AS ProfitMarginPct,
        COUNT(DISTINCT OrderID)                                    AS Orders,
        COUNT(DISTINCT CustomerKey)                                AS Customers,
        SUM(Quantity)                                              AS UnitsSold,
        CAST(SUM(Sales) / COUNT(DISTINCT OrderID) AS DECIMAL(10,2)) AS AvgOrderValue
FROM dbo.fact_sales;
GO

/* ---------------------------------------------------------------------
   Q2. YEAR-OVER-YEAR GROWTH  (LAG)
   --------------------------------------------------------------------- */
WITH yearly AS (
    SELECT d.[Year],
           SUM(f.Sales)  AS Sales,
           SUM(f.Profit) AS Profit
    FROM dbo.fact_sales f
    JOIN dbo.dim_date d ON d.DateKey = f.OrderDateKey
    GROUP BY d.[Year]
)
SELECT  [Year],
        CAST(Sales  AS DECIMAL(14,2))                                        AS Sales,
        CAST(Profit AS DECIMAL(14,2))                                        AS Profit,
        CAST(100.0 * Profit / Sales AS DECIMAL(5,2))                         AS MarginPct,
        CAST(100.0 * (Sales  - LAG(Sales)  OVER (ORDER BY [Year]))
                   / NULLIF(LAG(Sales)  OVER (ORDER BY [Year]), 0) AS DECIMAL(6,2)) AS SalesYoYPct,
        CAST(100.0 * (Profit - LAG(Profit) OVER (ORDER BY [Year]))
                   / NULLIF(LAG(Profit) OVER (ORDER BY [Year]), 0) AS DECIMAL(6,2)) AS ProfitYoYPct
FROM yearly
ORDER BY [Year];
GO

/* ---------------------------------------------------------------------
   Q3. MONTHLY TREND with YEAR-TO-DATE running total and same-month YoY
   --------------------------------------------------------------------- */
WITH monthly AS (
    SELECT d.[Year], d.[Month], d.YearMonth,
           SUM(f.Sales)  AS Sales,
           SUM(f.Profit) AS Profit
    FROM dbo.fact_sales f
    JOIN dbo.dim_date d ON d.DateKey = f.OrderDateKey
    GROUP BY d.[Year], d.[Month], d.YearMonth
)
SELECT  YearMonth,
        CAST(Sales  AS DECIMAL(12,2)) AS Sales,
        CAST(Profit AS DECIMAL(12,2)) AS Profit,
        CAST(SUM(Sales) OVER (PARTITION BY [Year] ORDER BY [Month]) AS DECIMAL(14,2)) AS YTD_Sales,
        CAST(100.0 * (Sales - LAG(Sales, 12) OVER (ORDER BY [Year], [Month]))
                   / NULLIF(LAG(Sales, 12) OVER (ORDER BY [Year], [Month]), 0) AS DECIMAL(7,2)) AS SalesYoYPct
FROM monthly
ORDER BY [Year], [Month];
GO

/* ---------------------------------------------------------------------
   Q4. CATEGORY / SUB-CATEGORY PROFITABILITY with ranking
   --------------------------------------------------------------------- */
SELECT  p.Category,
        p.SubCategory,
        CAST(SUM(f.Sales)  AS DECIMAL(14,2))                      AS Sales,
        CAST(SUM(f.Profit) AS DECIMAL(14,2))                      AS Profit,
        CAST(100.0 * SUM(f.Profit) / SUM(f.Sales) AS DECIMAL(6,2)) AS MarginPct,
        RANK() OVER (ORDER BY SUM(f.Profit) DESC)                 AS ProfitRank,
        CASE WHEN SUM(f.Profit) < 0 THEN 'LOSS-MAKING' ELSE '' END AS Flag
FROM dbo.fact_sales f
JOIN dbo.dim_product p ON p.ProductKey = f.ProductKey
GROUP BY p.Category, p.SubCategory
ORDER BY Profit DESC;
GO

/* ---------------------------------------------------------------------
   Q5. REGION PERFORMANCE and the 10 WORST STATES by profit
   --------------------------------------------------------------------- */
SELECT  g.Region,
        CAST(SUM(f.Sales)  AS DECIMAL(14,2))                       AS Sales,
        CAST(SUM(f.Profit) AS DECIMAL(14,2))                       AS Profit,
        CAST(100.0 * SUM(f.Profit) / SUM(f.Sales) AS DECIMAL(6,2)) AS MarginPct
FROM dbo.fact_sales f
JOIN dbo.dim_geography g ON g.GeographyKey = f.GeographyKey
GROUP BY g.Region
ORDER BY Profit DESC;

SELECT TOP 10
        g.State,
        CAST(SUM(f.Sales)  AS DECIMAL(14,2))                       AS Sales,
        CAST(SUM(f.Profit) AS DECIMAL(14,2))                       AS Profit,
        CAST(100.0 * SUM(f.Profit) / SUM(f.Sales) AS DECIMAL(6,2)) AS MarginPct
FROM dbo.fact_sales f
JOIN dbo.dim_geography g ON g.GeographyKey = f.GeographyKey
GROUP BY g.State
ORDER BY SUM(f.Profit) ASC;
GO

/* ---------------------------------------------------------------------
   Q6. DISCOUNT IMPACT: margin by discount band
   --------------------------------------------------------------------- */
SELECT  CASE WHEN Discount = 0     THEN '1) No discount'
             WHEN Discount <= 0.20 THEN '2) 1-20%'
             WHEN Discount <= 0.40 THEN '3) 21-40%'
             WHEN Discount <= 0.60 THEN '4) 41-60%'
             ELSE                       '5) Over 60%' END          AS DiscountBand,
        COUNT(*)                                                   AS OrderLines,
        CAST(SUM(Sales)  AS DECIMAL(14,2))                         AS Sales,
        CAST(SUM(Profit) AS DECIMAL(14,2))                         AS Profit,
        CAST(100.0 * SUM(Profit) / SUM(Sales) AS DECIMAL(6,2))     AS MarginPct
FROM dbo.fact_sales
GROUP BY CASE WHEN Discount = 0     THEN '1) No discount'
              WHEN Discount <= 0.20 THEN '2) 1-20%'
              WHEN Discount <= 0.40 THEN '3) 21-40%'
              WHEN Discount <= 0.60 THEN '4) 41-60%'
              ELSE                       '5) Over 60%' END
ORDER BY DiscountBand;
GO

/* ---------------------------------------------------------------------
   Q7. SUB-CATEGORIES: profit on deep-discounted (>20%) vs normal sales
   --------------------------------------------------------------------- */
SELECT  p.SubCategory,
        CAST(SUM(CASE WHEN f.Discount <= 0.20 THEN f.Profit ELSE 0 END) AS DECIMAL(14,2)) AS ProfitAt0to20Disc,
        CAST(SUM(CASE WHEN f.Discount >  0.20 THEN f.Profit ELSE 0 END) AS DECIMAL(14,2)) AS ProfitOver20Disc,
        CAST(SUM(f.Profit) AS DECIMAL(14,2))                                              AS TotalProfit
FROM dbo.fact_sales f
JOIN dbo.dim_product p ON p.ProductKey = f.ProductKey
GROUP BY p.SubCategory
ORDER BY ProfitOver20Disc ASC;
GO

/* ---------------------------------------------------------------------
   Q8. TOP 10 and BOTTOM 10 PRODUCTS by profit (ROW_NUMBER)
   --------------------------------------------------------------------- */
WITH prod AS (
    SELECT  p.ProductKey, p.ProductName, p.Category, p.SubCategory,
            SUM(f.Sales)  AS Sales,
            SUM(f.Profit) AS Profit
    FROM dbo.fact_sales f
    JOIN dbo.dim_product p ON p.ProductKey = f.ProductKey
    GROUP BY p.ProductKey, p.ProductName, p.Category, p.SubCategory
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (ORDER BY Profit DESC) AS rn_top,
           ROW_NUMBER() OVER (ORDER BY Profit ASC)  AS rn_bottom
    FROM prod
)
SELECT 'TOP 10' AS ListType, rn_top AS Pos, ProductName, Category, SubCategory,
       CAST(Sales AS DECIMAL(12,2)) AS Sales, CAST(Profit AS DECIMAL(12,2)) AS Profit
FROM ranked WHERE rn_top <= 10
UNION ALL
SELECT 'BOTTOM 10', rn_bottom, ProductName, Category, SubCategory,
       CAST(Sales AS DECIMAL(12,2)), CAST(Profit AS DECIMAL(12,2))
FROM ranked WHERE rn_bottom <= 10
ORDER BY ListType DESC, Pos;
GO

/* ---------------------------------------------------------------------
   Q9. CUSTOMER SEGMENTS (Consumer / Corporate / Home Office)
   --------------------------------------------------------------------- */
SELECT  c.Segment,
        COUNT(DISTINCT c.CustomerKey)                               AS Customers,
        COUNT(DISTINCT f.OrderID)                                   AS Orders,
        CAST(SUM(f.Sales)  AS DECIMAL(14,2))                        AS Sales,
        CAST(SUM(f.Profit) AS DECIMAL(14,2))                        AS Profit,
        CAST(100.0 * SUM(f.Profit) / SUM(f.Sales) AS DECIMAL(6,2))  AS MarginPct,
        CAST(SUM(f.Sales) / COUNT(DISTINCT c.CustomerKey) AS DECIMAL(10,2)) AS SalesPerCustomer
FROM dbo.fact_sales f
JOIN dbo.dim_customer c ON c.CustomerKey = f.CustomerKey
GROUP BY c.Segment
ORDER BY Sales DESC;
GO

/* ---------------------------------------------------------------------
   Q10. RFM CUSTOMER SEGMENTATION (NTILE)
        R = days since last order, F = number of orders, M = total sales
        Score 5 = best. CustomerKey is a tiebreaker so results are stable.
   --------------------------------------------------------------------- */
WITH base AS (
    SELECT  f.CustomerKey,
            MAX(d.FullDate)                                         AS LastOrder,
            COUNT(DISTINCT f.OrderID)                               AS Frequency,
            SUM(f.Sales)                                            AS Monetary
    FROM dbo.fact_sales f
    JOIN dbo.dim_date d ON d.DateKey = f.OrderDateKey
    GROUP BY f.CustomerKey
),
rfm AS (
    SELECT  CustomerKey, Frequency, Monetary,
            DATEDIFF(DAY, LastOrder, (SELECT DATEADD(DAY, 1, MAX(LastOrder)) FROM base)) AS Recency
    FROM base
),
scored AS (
    SELECT  *,
            NTILE(5) OVER (ORDER BY Recency DESC,  CustomerKey) AS R,
            NTILE(5) OVER (ORDER BY Frequency ASC, Monetary, CustomerKey) AS F,
            NTILE(5) OVER (ORDER BY Monetary ASC,  CustomerKey) AS M
    FROM rfm
),
labelled AS (
    SELECT  *,
            CASE WHEN R >= 4 AND F >= 4 AND M >= 4 THEN 'Champions'
                 WHEN R >= 3 AND F >= 3            THEN 'Loyal Customers'
                 WHEN R >= 4 AND F <= 2            THEN 'New / Recent Customers'
                 WHEN R <= 2 AND F >= 3            THEN 'At Risk'
                 WHEN R <= 2 AND F <= 2            THEN 'Lost / Hibernating'
                 ELSE                                   'Needs Attention' END AS RFM_Segment
    FROM scored
)
SELECT  RFM_Segment,
        COUNT(*)                                          AS Customers,
        CAST(SUM(Monetary) AS DECIMAL(14,2))              AS Sales,
        CAST(100.0 * SUM(Monetary) / SUM(SUM(Monetary)) OVER () AS DECIMAL(5,2)) AS PctOfSales,
        AVG(Recency)                                      AS AvgDaysSinceLastOrder,
        CAST(AVG(CAST(Frequency AS DECIMAL(6,2))) AS DECIMAL(5,2)) AS AvgOrders
FROM labelled
GROUP BY RFM_Segment
ORDER BY Sales DESC;
GO

/* ---------------------------------------------------------------------
   Q11. PARETO: how many customers generate 80% of sales?
   --------------------------------------------------------------------- */
WITH cust AS (
    SELECT CustomerKey, SUM(Sales) AS Sales
    FROM dbo.fact_sales
    GROUP BY CustomerKey
),
cum AS (
    SELECT  CustomerKey, Sales,
            SUM(Sales) OVER (ORDER BY Sales DESC, CustomerKey ROWS UNBOUNDED PRECEDING) AS CumSales,
            SUM(Sales) OVER ()                                                          AS TotalSales
    FROM cust
)
SELECT  COUNT(*)                                                         AS CustomersNeededFor80Pct,
        (SELECT COUNT(*) FROM cust)                                      AS TotalCustomers,
        CAST(100.0 * COUNT(*) / (SELECT COUNT(*) FROM cust) AS DECIMAL(5,2)) AS PctOfCustomers
FROM cum
WHERE CumSales - Sales < 0.80 * TotalSales;
GO

/* ---------------------------------------------------------------------
   Q12. SHIPPING: average ship days and margin by ship mode
   --------------------------------------------------------------------- */
SELECT  m.ShipMode,
        COUNT(DISTINCT f.OrderID)                                    AS Orders,
        CAST(AVG(CAST(DATEDIFF(DAY, od.FullDate, sd.FullDate) AS DECIMAL(5,2))) AS DECIMAL(4,2)) AS AvgShipDays,
        CAST(SUM(f.Sales)  AS DECIMAL(14,2))                         AS Sales,
        CAST(100.0 * SUM(f.Profit) / SUM(f.Sales) AS DECIMAL(6,2))   AS MarginPct
FROM dbo.fact_sales f
JOIN dbo.dim_ship_mode m ON m.ShipModeKey = f.ShipModeKey
JOIN dbo.dim_date od     ON od.DateKey    = f.OrderDateKey
JOIN dbo.dim_date sd     ON sd.DateKey    = f.ShipDateKey
GROUP BY m.ShipMode
ORDER BY AvgShipDays;
GO

/* ---------------------------------------------------------------------
   Q13. LOSS-MAKING ORDER LINES: how big is the leak?
   --------------------------------------------------------------------- */
SELECT  CASE WHEN Profit < 0 THEN 'Loss-making lines' ELSE 'Profitable lines' END AS LineType,
        COUNT(*)                                                      AS OrderLines,
        CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS PctOfLines,
        CAST(SUM(Sales)  AS DECIMAL(14,2))                            AS Sales,
        CAST(SUM(Profit) AS DECIMAL(14,2))                            AS Profit,
        CAST(AVG(Discount) AS DECIMAL(4,2))                           AS AvgDiscount
FROM dbo.fact_sales
GROUP BY CASE WHEN Profit < 0 THEN 'Loss-making lines' ELSE 'Profitable lines' END;
GO
