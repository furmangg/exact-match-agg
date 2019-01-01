/*
This code sample is from https://github.com/furmangg/exact-match-agg
and should be run against Azure SQL DW on top of the AdventureWorksDW sample
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


--exec usp_ProductAggSignatureForDateRange @DateRangeName = 'MTD'