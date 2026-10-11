/* =====================================================================
   Superstore Sales & Profitability Project
   Script 03 - Flat view for Excel (Power BI uses the star schema tables)
   Run AFTER scripts 01 and 02. Select everything (Ctrl+A) and press F5.
   ===================================================================== */
USE SuperstoreDB;
GO

CREATE OR ALTER VIEW dbo.vw_sales_flat AS
SELECT  f.SalesKey,
        f.OrderID,
        od.FullDate                              AS OrderDate,
        od.[Year]                                AS OrderYear,
        od.QuarterName                           AS OrderQuarter,
        od.[Month]                               AS OrderMonthNo,
        od.MonthName                             AS OrderMonth,
        od.YearMonth                             AS OrderYearMonth,
        sd.FullDate                              AS ShipDate,
        DATEDIFF(DAY, od.FullDate, sd.FullDate)  AS ShipDays,
        m.ShipMode,
        c.CustomerID,
        c.CustomerName,
        c.Segment,
        g.Region,
        g.State,
        g.City,
        g.PostalCode,
        p.ProductID,
        p.ProductName,
        p.Category,
        p.SubCategory,
        f.Sales,
        f.Quantity,
        f.Discount,
        f.Profit,
        f.Cost
FROM dbo.fact_sales     f
JOIN dbo.dim_date       od ON od.DateKey      = f.OrderDateKey
JOIN dbo.dim_date       sd ON sd.DateKey      = f.ShipDateKey
JOIN dbo.dim_customer   c  ON c.CustomerKey   = f.CustomerKey
JOIN dbo.dim_product    p  ON p.ProductKey    = f.ProductKey
JOIN dbo.dim_geography  g  ON g.GeographyKey  = f.GeographyKey
JOIN dbo.dim_ship_mode  m  ON m.ShipModeKey   = f.ShipModeKey;
GO

-- Check: expect 9994 rows, Sales 2297200.8603, Profit 286397.0217
SELECT COUNT(*) AS Rows_, SUM(Sales) AS TotalSales, SUM(Profit) AS TotalProfit
FROM dbo.vw_sales_flat;
GO
