/* =====================================================================
   Superstore Sales & Profitability Project
   Script 01 - Database, staging import, star schema, validation
   Target: SQL Server 2019+ (tested logic for SQL Server 2025 / SSMS 22)

   BEFORE YOU RUN:
   1. Create the folder C:\Data
   2. Copy the Kaggle CSV there and rename it to:  Superstore.csv
   3. Run this script section by section (highlight + F5) the first time
   ===================================================================== */

/* ---------- 0. DATABASE ---------- */
USE master;
GO
IF DB_ID('SuperstoreDB') IS NULL CREATE DATABASE SuperstoreDB;
GO
USE SuperstoreDB;
GO

/* ---------- 1. STAGING TABLE (raw text, nothing can fail on load) ---------- */
DROP TABLE IF EXISTS dbo.stg_superstore;
CREATE TABLE dbo.stg_superstore (
    Row_ID         NVARCHAR(20),
    Order_ID       NVARCHAR(30),
    Order_Date     NVARCHAR(20),
    Ship_Date      NVARCHAR(20),
    Ship_Mode      NVARCHAR(30),
    Customer_ID    NVARCHAR(20),
    Customer_Name  NVARCHAR(100),
    Segment        NVARCHAR(30),
    Country        NVARCHAR(50),
    City           NVARCHAR(100),
    State          NVARCHAR(50),
    Postal_Code    NVARCHAR(20),
    Region         NVARCHAR(20),
    Product_ID     NVARCHAR(30),
    Category       NVARCHAR(50),
    Sub_Category   NVARCHAR(50),
    Product_Name   NVARCHAR(255),
    Sales          NVARCHAR(30),
    Quantity       NVARCHAR(10),
    Discount       NVARCHAR(10),
    Profit         NVARCHAR(30)
);
GO

/* ---------- 2. LOAD THE CSV ----------
   Notes: file is Windows-1252 encoded and uses LF line endings,
   so CODEPAGE and ROWTERMINATOR matter. */
BULK INSERT dbo.stg_superstore
FROM 'C:\Data\Superstore.csv'
WITH (
    FORMAT          = 'CSV',
    FIELDQUOTE      = '"',
    FIRSTROW        = 2,
    CODEPAGE        = '1252',
    ROWTERMINATOR   = '0x0a',
    TABLOCK
);
GO

/* ---------- 3. CHECK THE LOAD ----------
   Expected: 9994 rows, Sales ~ 2,297,200.86, Profit ~ 286,397.02 */
SELECT  COUNT(*)                                     AS RowsLoaded,
        SUM(TRY_CONVERT(DECIMAL(14,4), Sales))       AS TotalSales,
        SUM(TRY_CONVERT(DECIMAL(14,4), Profit))      AS TotalProfit
FROM dbo.stg_superstore;
GO

/* ---------- 4. DATA QUALITY CHECKS (all should return 0) ---------- */
SELECT 'Unparseable order dates' AS Chk, COUNT(*) AS Bad FROM dbo.stg_superstore WHERE TRY_CONVERT(DATE, Order_Date, 101) IS NULL
UNION ALL
SELECT 'Unparseable ship dates',  COUNT(*) FROM dbo.stg_superstore WHERE TRY_CONVERT(DATE, Ship_Date, 101) IS NULL
UNION ALL
SELECT 'Ship before order',       COUNT(*) FROM dbo.stg_superstore WHERE TRY_CONVERT(DATE, Ship_Date, 101) < TRY_CONVERT(DATE, Order_Date, 101)
UNION ALL
SELECT 'Non-numeric measures',    COUNT(*) FROM dbo.stg_superstore
    WHERE TRY_CONVERT(DECIMAL(14,4), Sales) IS NULL OR TRY_CONVERT(DECIMAL(14,4), Profit) IS NULL
       OR TRY_CONVERT(INT, Quantity) IS NULL OR TRY_CONVERT(DECIMAL(4,2), Discount) IS NULL
UNION ALL
SELECT 'Duplicate Row_ID',        COUNT(*) - COUNT(DISTINCT Row_ID) FROM dbo.stg_superstore
UNION ALL
SELECT 'Blank key fields',        COUNT(*) FROM dbo.stg_superstore
    WHERE NULLIF(TRIM(Order_ID),'') IS NULL OR NULLIF(TRIM(Customer_ID),'') IS NULL OR NULLIF(TRIM(Product_ID),'') IS NULL;
GO

/* ---------- 5. STAR SCHEMA TABLES ---------- */
DROP TABLE IF EXISTS dbo.fact_sales;
DROP TABLE IF EXISTS dbo.dim_date;
DROP TABLE IF EXISTS dbo.dim_customer;
DROP TABLE IF EXISTS dbo.dim_product;
DROP TABLE IF EXISTS dbo.dim_geography;
DROP TABLE IF EXISTS dbo.dim_ship_mode;
GO

-- Date dimension (extends to 2018 because late-2017 orders ship in Jan 2018)
CREATE TABLE dbo.dim_date (
    DateKey      INT          NOT NULL PRIMARY KEY,   -- yyyymmdd
    FullDate     DATE         NOT NULL,
    [Year]       INT          NOT NULL,
    [Quarter]    INT          NOT NULL,
    QuarterName  CHAR(2)      NOT NULL,
    [Month]      INT          NOT NULL,
    MonthName    VARCHAR(10)  NOT NULL,
    YearMonth    CHAR(7)      NOT NULL,               -- 2016-11
    WeekOfYear   INT          NOT NULL,
    DayName      VARCHAR(10)  NOT NULL,
    IsWeekend    BIT          NOT NULL
);

CREATE TABLE dbo.dim_customer (
    CustomerKey   INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID    NVARCHAR(20)  NOT NULL UNIQUE,
    CustomerName  NVARCHAR(100) NOT NULL,
    Segment       NVARCHAR(30)  NOT NULL
);

-- Some Product IDs carry more than one name in the source, so the
-- natural key here is ProductID + ProductName (1,894 rows).
CREATE TABLE dbo.dim_product (
    ProductKey    INT IDENTITY(1,1) PRIMARY KEY,
    ProductID     NVARCHAR(30)  NOT NULL,
    ProductName   NVARCHAR(255) NOT NULL,
    Category      NVARCHAR(50)  NOT NULL,
    SubCategory   NVARCHAR(50)  NOT NULL,
    CONSTRAINT UQ_dim_product UNIQUE (ProductID, ProductName)
);

CREATE TABLE dbo.dim_geography (
    GeographyKey  INT IDENTITY(1,1) PRIMARY KEY,
    Country       NVARCHAR(50)  NOT NULL,
    Region        NVARCHAR(20)  NOT NULL,
    State         NVARCHAR(50)  NOT NULL,
    City          NVARCHAR(100) NOT NULL,
    PostalCode    CHAR(5)       NOT NULL,             -- text, keeps leading zeros
    CONSTRAINT UQ_dim_geography UNIQUE (Country, Region, State, City, PostalCode)
);

CREATE TABLE dbo.dim_ship_mode (
    ShipModeKey   INT IDENTITY(1,1) PRIMARY KEY,
    ShipMode      NVARCHAR(30) NOT NULL UNIQUE
);

-- Fact table. Grain = one order line (one row of the source file)
CREATE TABLE dbo.fact_sales (
    SalesKey       INT           NOT NULL PRIMARY KEY,   -- source Row ID
    OrderID        NVARCHAR(30)  NOT NULL,
    OrderDateKey   INT           NOT NULL REFERENCES dbo.dim_date(DateKey),
    ShipDateKey    INT           NOT NULL REFERENCES dbo.dim_date(DateKey),
    CustomerKey    INT           NOT NULL REFERENCES dbo.dim_customer(CustomerKey),
    ProductKey     INT           NOT NULL REFERENCES dbo.dim_product(ProductKey),
    GeographyKey   INT           NOT NULL REFERENCES dbo.dim_geography(GeographyKey),
    ShipModeKey    INT           NOT NULL REFERENCES dbo.dim_ship_mode(ShipModeKey),
    Sales          DECIMAL(14,4) NOT NULL,
    Quantity       INT           NOT NULL,
    Discount       DECIMAL(4,2)  NOT NULL,
    Profit         DECIMAL(14,4) NOT NULL,
    Cost           AS (Sales - Profit) PERSISTED         -- derived: cost of goods + costs
);
CREATE INDEX IX_fact_sales_order    ON dbo.fact_sales (OrderID);
CREATE INDEX IX_fact_sales_date     ON dbo.fact_sales (OrderDateKey);
CREATE INDEX IX_fact_sales_product  ON dbo.fact_sales (ProductKey);
CREATE INDEX IX_fact_sales_customer ON dbo.fact_sales (CustomerKey);
GO

/* ---------- 6. POPULATE DIMENSIONS ---------- */
;WITH d AS (
    SELECT CAST('2014-01-01' AS DATE) AS dt
    UNION ALL
    SELECT DATEADD(DAY, 1, dt) FROM d WHERE dt < '2018-12-31'
)
INSERT INTO dbo.dim_date (DateKey, FullDate, [Year], [Quarter], QuarterName, [Month], MonthName,
                          YearMonth, WeekOfYear, DayName, IsWeekend)
SELECT  CONVERT(INT, CONVERT(CHAR(8), dt, 112)),
        dt,
        YEAR(dt),
        DATEPART(QUARTER, dt),
        'Q' + CAST(DATEPART(QUARTER, dt) AS CHAR(1)),
        MONTH(dt),
        DATENAME(MONTH, dt),
        CONVERT(CHAR(7), dt, 23),
        DATEPART(ISO_WEEK, dt),
        DATENAME(WEEKDAY, dt),
        CASE WHEN DATENAME(WEEKDAY, dt) IN ('Saturday','Sunday') THEN 1 ELSE 0 END
FROM d
OPTION (MAXRECURSION 0);

INSERT INTO dbo.dim_customer (CustomerID, CustomerName, Segment)
SELECT DISTINCT TRIM(Customer_ID), TRIM(Customer_Name), TRIM(Segment)
FROM dbo.stg_superstore;

INSERT INTO dbo.dim_product (ProductID, ProductName, Category, SubCategory)
SELECT DISTINCT TRIM(Product_ID), TRIM(Product_Name), TRIM(Category), TRIM(Sub_Category)
FROM dbo.stg_superstore;

-- Postal codes lost their leading zeros in the CSV (e.g. 2138 -> 02138); restore them
INSERT INTO dbo.dim_geography (Country, Region, State, City, PostalCode)
SELECT DISTINCT TRIM(Country), TRIM(Region), TRIM(State), TRIM(City),
       RIGHT('00000' + TRIM(Postal_Code), 5)
FROM dbo.stg_superstore;

INSERT INTO dbo.dim_ship_mode (ShipMode)
SELECT DISTINCT TRIM(Ship_Mode) FROM dbo.stg_superstore;
GO

/* ---------- 7. POPULATE FACT TABLE ---------- */
INSERT INTO dbo.fact_sales (SalesKey, OrderID, OrderDateKey, ShipDateKey, CustomerKey, ProductKey,
                            GeographyKey, ShipModeKey, Sales, Quantity, Discount, Profit)
SELECT  CAST(s.Row_ID AS INT),
        TRIM(s.Order_ID),
        CONVERT(INT, CONVERT(CHAR(8), TRY_CONVERT(DATE, s.Order_Date, 101), 112)),
        CONVERT(INT, CONVERT(CHAR(8), TRY_CONVERT(DATE, s.Ship_Date,  101), 112)),
        c.CustomerKey,
        p.ProductKey,
        g.GeographyKey,
        m.ShipModeKey,
        CAST(s.Sales    AS DECIMAL(14,4)),
        CAST(s.Quantity AS INT),
        CAST(s.Discount AS DECIMAL(4,2)),
        CAST(s.Profit   AS DECIMAL(14,4))
FROM dbo.stg_superstore s
JOIN dbo.dim_customer  c ON c.CustomerID = TRIM(s.Customer_ID)
JOIN dbo.dim_product   p ON p.ProductID = TRIM(s.Product_ID) AND p.ProductName = TRIM(s.Product_Name)
JOIN dbo.dim_geography g ON g.Country = TRIM(s.Country) AND g.Region = TRIM(s.Region)
                        AND g.State = TRIM(s.State) AND g.City = TRIM(s.City)
                        AND g.PostalCode = RIGHT('00000' + TRIM(s.Postal_Code), 5)
JOIN dbo.dim_ship_mode m ON m.ShipMode = TRIM(s.Ship_Mode);
GO

/* ---------- 8. RECONCILIATION (fact must match staging exactly) ---------- */
SELECT 'staging' AS Src, COUNT(*) AS Rows_, SUM(TRY_CONVERT(DECIMAL(14,4), Sales)) AS Sales, SUM(TRY_CONVERT(DECIMAL(14,4), Profit)) AS Profit
FROM dbo.stg_superstore
UNION ALL
SELECT 'fact_sales', COUNT(*), SUM(Sales), SUM(Profit) FROM dbo.fact_sales;

SELECT 'dim_date' AS TableName, COUNT(*) AS Rows_ FROM dbo.dim_date
UNION ALL SELECT 'dim_customer',  COUNT(*) FROM dbo.dim_customer
UNION ALL SELECT 'dim_product',   COUNT(*) FROM dbo.dim_product
UNION ALL SELECT 'dim_geography', COUNT(*) FROM dbo.dim_geography
UNION ALL SELECT 'dim_ship_mode', COUNT(*) FROM dbo.dim_ship_mode
UNION ALL SELECT 'fact_sales',    COUNT(*) FROM dbo.fact_sales;
/* Expected rows: dim_date 1826, dim_customer 793, dim_product 1894,
   dim_geography 632, dim_ship_mode 4, fact_sales 9994 */
GO
