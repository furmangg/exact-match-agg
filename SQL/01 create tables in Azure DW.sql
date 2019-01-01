/*
This code sample is from https://github.com/furmangg/exact-match-agg
and should be run against Azure SQL DW on top of the AdventureWorksDW sample
*/
create table numbers (
 n int)
GO

insert numbers
select 1
union all
select 2
union all
select 3
union all
select 4
union all
select 5
union all
select 6
union all
select 7
union all
select 8
union all
select 9
union all
select 10
union all
select 11
union all
select 12

insert numbers
select 13
union all
select 14
union all
select 15
union all
select 16
union all
select 17
union all
select 18
union all
select 19
union all
select 20
union all
select 21
union all
select 22
union all
select 23
union all
select 24


GO


create table DimDateLarge
with (heap, distribution=replicate)
as
select DateKey = (YEAR(FullDateAlternateKey) * 10000) + (MONTH(FullDateAlternateKey) * 100) + DAY(FullDateAlternateKey)
, FullDateAlternateKey
, DayNumberOfWeek = DATEPart(DW, FullDateAlternateKey)
, EnglishDayNameOfWeek = DATENAME(Dw, FullDateAlternateKey)
, EnglishMonthName = DATENAME(Month, FullDateAlternateKey)
, MonthNumberOfYear = MONTH(FullDateAlternateKey)
, CalendarYear = YEAR(FullDateAlternateKey)
from (
	select dateadd(day,rownum-1,'2013-01-01') as FullDateAlternateKey
	from (
		select ROW_NUMBER() OVER (ORDER BY n1.n) as rownum
		from numbers n1
		cross join numbers n2
		cross join numbers n3
	) d
) d
where FullDateAlternateKey between '2013-01-01' and '2018-12-31';

create statistics STAT_DateKey on DimDateLarge (DateKey);

GO



create table DimStore with (distribution=replicate, heap)
as
select CustomerKey+(select count(*) from DimCustomer)*(n.n-1) as StoreKey
,CustomerAlternateKey+cast(n.n as varchar) as StoreNumber
,g.EnglishCountryRegionName as Country
,g.CountryRegionCode + c.Gender as Zone
,g.CountryRegionCode + c.Gender + left(FirstName,1) as District
,cast(case when TotalChildren < 4 then 1 else 0 end as bit) as SameStoreSalesFlag
from DimCustomer c
join DimGeography g on g.GeographyKey = c.GeographyKey
cross join numbers n
where n.n <= 3



if object_id('FactSales') is not null
	drop table FactSales;

create table FactSales with (clustered columnstore index,distribution=hash(StoreKey))
as
select f.ProductKey
, od.DateKey
, StoreKey = CustomerKey+(select count(*) from DimCustomer)*(n.n-1)
, cast(CustomerKey+(select count(*) from DimCustomer)*(n.n-1) as bigint)*100000000 + DateKey as StoreDate
, f.SalesTerritoryKey
, OrderQuantity = cast(f.OrderQuantity * n.n * case when od.DateKey>20180000 and ProductKey>376 then 1.6 else 1 end as int)
, ExtendedAmount = f.UnitPrice * cast(f.OrderQuantity * n.n * case when od.DateKey>20180000 and ProductKey>376 then 1.6 else 1 end as int)
from FactInternetSales f
cross join (select n from Numbers where n between 1 and 3) n
cross join DimDateLarge od;


alter table FactSales rebuild;

CREATE STATISTICS STAT_DateKey on FactSales (DateKey)
CREATE STATISTICS STAT_ProductKey on FactSales (ProductKey)
CREATE STATISTICS STAT_StoreKey on FactSales (StoreKey)




GO

create view vwDimDate
as
select DateKey
, FullDateAlternateKey
, DayNumberOfWeek
, EnglishDayNameOfWeek
, EnglishMonthName
, MonthNumberOfYear
, CalendarYear
, YtdFlag = cast(case when DateKey between 20180101 and 20181217 then 1 else 0 end as bit)
, PriorYtdFlag = cast(case when DateKey between 20170101 and 20171217 then 1 else 0 end as bit)
, MtdFlag = cast(case when DateKey between 20181201 and 20181217 then 1 else 0 end as bit)
, PriorMtdFlag = cast(case when DateKey between 20171201 and 20171217 then 1 else 0 end as bit)
, CompletedThreeMonthsFlag = cast(case when DateKey between 20180901 and 20181130 then 1 else 0 end as bit)
, PriorCompletedThreeMonthsFlag = cast(case when DateKey between 20170901 and 20171130 then 1 else 0 end as bit)
from DimDateLarge


GO

create view vwDimProduct
as
select p.ProductKey
,p.ProductAlternateKey as ProductCode
,p.EnglishProductName as Product
,p.FinishedGoodsFlag
,p.Color
,p.SafetyStockLevel
,p.SizeRange
,p.ProductLine
,p.ModelName
,isnull(s.EnglishProductSubcategoryName,'Unknown') as ProductSubcategory
,isnull(s.ProductSubcategoryAlternateKey,99) as ProductSubcategoryCode
,isnull(c.EnglishProductCategoryName,'Unknown') as ProductCategory
,isnull(c.ProductCategoryAlternateKey,99) as ProductCategoryCode
,(ProductKey*ProductKey*100)%77 as ExponentModProductKey
from DimProduct p
left join DimProductSubcategory s on s.ProductSubcategoryKey = p.ProductSubcategoryKey
left join DimProductCategory c on c.ProductCategoryKey = s.ProductCategoryKey

