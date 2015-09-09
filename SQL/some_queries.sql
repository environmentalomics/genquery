create view genquery.count_allocations_by_block as
(
select fromcode
, count(g.barcode) as allocated
from barcode_allocation ba 
left outer join data.generic g ON
        (g.barcode >= ba.fromcode AND g.barcode <= ba.tocode)
where fromcode = 11900
group by username, fromcode
);

grant select on genquery.count_allocations_by_block to webuser;

create view genquery.count_disposals_by_block as
(
select fromcode
, count(d.barcode) as disposed 
from barcode_allocation ba 
left outer join barcode_deletion d ON
        (d.barcode >= ba.fromcode AND d.barcode <= ba.tocode)
where fromcode = 11900
group by username, fromcode
);

grant select on genquery.count_disposals_by_block to webuser;

create view genquery.count_active_by_block as
(
select fromcode
, count(g.barcode) as active
from barcode_allocation ba 
left outer join data.generic g ON
        (g.barcode >= ba.fromcode AND g.barcode <= ba.tocode
	 and not exists (select barcode from barcode_deletion d where
	 d.barcode = g.barcode
	))
where fromcode = 11900
group by username, fromcode
);

grant select on genquery.count_active_by_block to webuser;