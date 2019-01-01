/*
This code sample is from https://github.com/furmangg/exact-match-agg
and should be run against Azure SQL DW on top of the AdventureWorksDW sample
*/
create table dbo.DimProductAggSignature (
 ProductAggSignatureKey int not null identity(1,1)
,CountProductKey int null
,MinProductKey bigint null
,MaxProductKey bigint null
,SumProductKey bigint null
,SumExponentModProductKey bigint null
)

GO

if object_id('tempdb..#Product') is not null
	drop table #Product

create table #Product
with (distribution=round_robin, heap)
as
select p.ProductKey
, p.FinishedGoodsFlag
, p.Color
, p.ModelName
, cast(p.ProductSubcategoryCode as varchar) as ProductSubcategoryCode
, p.ProductSubcategory
, cast(p.ProductCategoryCode as varchar) as ProductCategoryCode
, p.ProductCategory
FROM vwDimProduct p;




if object_id('tempdb..#ProductRollups') is not null
	drop table #ProductRollups

create table #ProductRollups
with (distribution=hash(Grouper1), heap)
as
select ProductKey, '--GrandTotal--' as Grouper1, Color, FinishedGoodsFlag, cast('All' as varchar(200)) as GroupType
FROM #Product
union all
select ProductKey, Color as Grouper1, Color, FinishedGoodsFlag, 'Color' as GroupType
FROM #Product
union all
select ProductKey, ModelName as Grouper1, Color, FinishedGoodsFlag, 'ModelName' as GroupType
FROM #Product
union all
select ProductKey, ProductSubcategoryCode as Grouper1, Color, FinishedGoodsFlag, 'ProductSubcategoryCode' as GroupType
FROM #Product
union all
select ProductKey, ProductSubcategory as Grouper1, Color, FinishedGoodsFlag, 'ProductSubcategory' as GroupType
FROM #Product
union all
select ProductKey, ProductCategoryCode as Grouper1, Color, FinishedGoodsFlag, 'ProductCategoryCode' as GroupType
FROM #Product
union all
select ProductKey, ProductCategory as Grouper1, Color, FinishedGoodsFlag, 'ProductCategory' as GroupType
FROM #Product
union all
select ProductKey, isnull(ModelName,'')+'-'+isnull(Color,'') as Grouper1, Color, FinishedGoodsFlag, 'ModelName-Color' as GroupType
FROM #Product;


if object_id('tempdb..#ProductAggSignature') is not null
	drop table #ProductAggSignature

create table #ProductAggSignature
with (distribution=round_robin, heap)
as
	select ProductKey
	, Grouper1
	, Grouper2
	, Grouper3
	, GroupType
	, CountProductKey = count(*) OVER (PARTITION BY Grouper1, Grouper2, Grouper3, GroupType)
	, MinProductKey = min(ProductKey) OVER (PARTITION BY Grouper1, Grouper2, Grouper3, GroupType)
	, MaxProductKey = max(ProductKey) OVER (PARTITION BY Grouper1, Grouper2, Grouper3, GroupType)
	, SumProductKey = sum(ProductKey) OVER (PARTITION BY Grouper1, Grouper2, Grouper3, GroupType)
	, SumExponentModProductKey = sum((ProductKey*ProductKey*100)%77) OVER (PARTITION BY Grouper1, Grouper2, Grouper3, GroupType)
	from (
		select ProductKey, Grouper1, null as Grouper2, null as Grouper3, GroupType
		FROM #ProductRollups
		union all
		select ProductKey, Grouper1, 'Greys' as Grouper2, null as Grouper3, GroupType+'-Greys' as GroupType
		FROM #ProductRollups
		where Color in ('Black','Grey')
		union all
		select ProductKey, Grouper1, cast(FinishedGoodsFlag as varchar) as Grouper2, null as Grouper3, GroupType+'-FinishedGoods' as GroupType
		FROM #ProductRollups
		where FinishedGoodsFlag=1
		union all
		select ProductKey, Grouper1, 'Greys' as Grouper2, cast(FinishedGoodsFlag as varchar) as Grouper3, GroupType+'-Greys-FinishedGoods' as GroupType
		FROM #ProductRollups
		where Color in ('Black','Grey') and FinishedGoodsFlag=1
	) x;



/*
--922 distinct groups created, but that will compress down into 205 DimProductAggSignature rows 
--for example, when a ProductCategory has only one ProductSubcategory they are considered the same "agg"
select count(*) 
from (
 select distinct Grouper1, Grouper2, Grouper3, GroupType 
 from #ProductAggSignature
) x
*/

truncate table dbo.DimProductAggSignature

insert into dbo.DimProductAggSignature (CountProductKey, MinProductKey, MaxProductKey, SumProductKey, SumExponentModProductKey)
select distinct CountProductKey, MinProductKey, MaxProductKey, SumProductKey, SumExponentModProductKey
from #ProductAggSignature
union all
select null, null, null, null, null --insert the row that corresponds with the BLANK() row in the Product dimension

/*

select * from dbo.DimProductAggSignature where CountProductKey is null

select distinct GroupType, CountProductKey, MinProductKey, MaxProductKey, SumProductKey, SumExponentModProductKey
from #ProductAggSignature
order by 2,3,4,5,6

select * from dbo.DimProductAggSignature
*/



if object_id('dbo.BridgeProductAggSignature') is not null
	drop table dbo.BridgeProductAggSignature

create table dbo.BridgeProductAggSignature
with (distribution=REPLICATE, clustered columnstore index)
as
select distinct pas.ProductKey, d.ProductAggSignatureKey
from #ProductAggSignature pas
join dbo.DimProductAggSignature d
 on d.CountProductKey = pas.CountProductKey
 and d.MinProductKey = pas.MinProductKey
 and d.MaxProductKey = pas.MaxProductKey
 and d.SumProductKey = pas.SumProductKey
 and d.SumExponentModProductKey = pas.SumExponentModProductKey
--order by pas.ProductKey

alter table dbo.BridgeProductAggSignature rebuild;

create statistics STAT_ProductKey on dbo.BridgeProductAggSignature (ProductKey);
create statistics STAT_ProductAggSignatureKey on dbo.BridgeProductAggSignature (ProductAggSignatureKey);

--warm up the replicated table caching it on each node
declare @ProductAggSignatureKey int = (select min(ProductAggSignatureKey) from dbo.BridgeProductAggSignature)

if object_id('dbo.DimDateRange') is not null
	drop table dbo.DimDateRange

create table dbo.DimDateRange
with (distribution=round_robin, heap)
as
--if two date ranges have the exact same signature then just keep one or else cube numbers will be duplicated
SELECT DateRangeKey, MinDateKey, MaxDateKey, max(DateRangeName) as DateRangeName
from (
	SELECT DateRangeKey = cast(cast(max(DateKey) as bigint)*1000+count(*) as bigint)
	,MinDateKey = min(DateKey)
	,MaxDateKey = max(DateKey)
	,DateRangeName = cast(DateRangeName as varchar(50))
	from (
		select DateKey, DateRangeName = 'YTD'
		FROM vwDimDate
		where YtdFlag=1
		UNION ALL
		select DateKey, DateRangeName = 'PriorYTD'
		FROM vwDimDate
		where PriorYtdFlag=1
		UNION ALL
		select DateKey, DateRangeName = 'MTD'
		FROM vwDimDate
		where MtdFlag=1
		UNION ALL
		select DateKey, DateRangeName = 'PriorMTD'
		FROM vwDimDate
		where PriorMtdFlag=1
		UNION ALL
		select DateKey, DateRangeName = 'CompletedThreeMonths-Total'
		FROM vwDimDate
		where CompletedThreeMonthsFlag=1
		UNION ALL
		select DateKey, DateRangeName = 'PriorCompletedThreeMonths-Total'
		FROM vwDimDate
		where PriorCompletedThreeMonthsFlag=1
		UNION ALL
		select DateKey, DateRangeName = 'CompletedThreeMonths-' + CAST(DENSE_RANK() OVER (ORDER BY CalendarYear desc, MonthNumberOfYear desc) as varchar)
		FROM vwDimDate
		where CompletedThreeMonthsFlag=1
		UNION ALL
		select DateKey, DateRangeName = 'PriorCompletedThreeMonths-' + CAST(DENSE_RANK() OVER (ORDER BY CalendarYear desc, MonthNumberOfYear desc) as varchar)
		FROM vwDimDate
		where PriorCompletedThreeMonthsFlag=1
	) d
	group by DateRangeName
) d
group by DateRangeKey, MinDateKey, MaxDateKey;

--select * from dbo.DimDateRange order by 1
