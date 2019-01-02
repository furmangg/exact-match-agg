/*
This code sample is from https://github.com/furmangg/exact-match-agg
and should be run against Azure SQL DW on top of the AdventureWorksDW sample

We chose to create a sproc which takes in the DateRangeName as a parameter and calculates the pre-aggregations
If there are 20 date ranges, then in SSAS we create 20 partitions. Each partition calls this sproc like the following.
This allows multiple date ranges to be pre-aggregated in parallel.
exec usp_ProductAggSignatureForDateRange @DateRangeName = 'MTD'
*/
if object_id('dbo.usp_ProductAggSignatureForDateRange') is not null
	drop proc dbo.usp_ProductAggSignatureForDateRange
GO

create proc dbo.usp_ProductAggSignatureForDateRange @DateRangeName varchar(50)
as
begin
	declare @MinDateKey int = (select MinDateKey from dbo.DimDateRange where DateRangeName = @DateRangeName)
	declare @MaxDateKey int = (select MaxDateKey from dbo.DimDateRange where DateRangeName = @DateRangeName)
	declare @DateRangeKey bigint = (select DateRangeKey from dbo.DimDateRange where DateRangeName = @DateRangeName)

	select distinct f.StoreKey
	,DateRangeKey = @DateRangeKey
	,p.ProductAggSignatureKey
	,count(distinct f.DateKey) as StoreDayCount
	from (
		select *
		from dbo.FactSales
		where DateKey between @MinDateKey and @MaxDateKey
	) f
	join dbo.BridgeProductAggSignature p on p.ProductKey = f.ProductKey
	group by f.StoreKey
	,p.ProductAggSignatureKey 
end

