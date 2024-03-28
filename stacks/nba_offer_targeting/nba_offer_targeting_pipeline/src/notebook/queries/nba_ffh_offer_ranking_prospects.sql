

CREATE OR REPLACE PROCEDURE nba_offer_targeting.bq_sp_nba_ffh_offer_ranking_prospects()

-- This stored procedure pulls the list of customers at cust_id + ban + lpds_id level who are eligible for Casa IRPC Offers

BEGIN

	DECLARE maxDate date;
	SET maxDate = (SELECT DATE(MAX(prod_instnc_ts)) FROM `cio-datahub-enterprise-pr-183a.ent_cust_cust.bq_prod_instnc_snpsht` WHERE DATE(prod_instnc_ts) > DATE_ADD(CURRENT_DATE(), INTERVAL -7 DAY)); 

	CREATE OR REPLACE TABLE nba_offer_targeting.nba_ffh_offer_ranking_prospects AS 

	WITH mob_ban_lpds_id AS (
		SELECT DISTINCT
			 base.consldt_cust_bus_cust_id AS cust_id,
			 base.consldt_cust_bus_cust_src_id AS cust_src_id,
			 base.bacct_bus_bacct_num AS ban,
			 base.bacct_bus_bacct_num_src_id AS ban_src_id,
			 DATE(base.bacct_bacct_create_ts) AS ban_create_dt,
			 lpds.lpds_id
		FROM `cio-datahub-enterprise-pr-183a.ent_cust_cust.bq_prod_instnc_snpsht` AS base
		INNER JOIN `bi-srv-divgdsa-pr-098bdd.common.bq_mobility_active_data` AS lpds
		  ON SAFE_CAST(lpds.ban AS INT64) = base.bacct_bus_bacct_num
		WHERE DATE(base.prod_instnc_ts) = maxDate
		 AND base.bacct_brand_id = 1  # TELUS
		 AND base.pi_prod_instnc_stat_cd != 'C'
		 AND base.bacct_bacct_typ_cd IN ('I','C')
		 AND base.bacct_bacct_subtyp_cd IN ('I','R','E')
		 AND base.bus_prod_instnc_src_id = 130
		 AND lpds.part_dt = CURRENT_DATE('America/Vancouver')-1
		 AND lpds.lpds_id IS NOT NULL
	), 

	nba_ranking AS (
		SELECT b.ban, b.lpds_id, a.ranks AS nba_ranking,
		case 
		when reco = 'hsic' then 'Cross-sell'  
		when reco = 'ht' then 'Cross-sell' 
		when reco = 'hs' then 'Cross-sell' 
		when reco = 'hts' then 'Cross-sell' 
		when reco = 'shs' then 'Cross-sell' 
		when reco = 'tv' then 'Cross-sell' 
		when reco = 'sws' then 'Cross-sell' 
		when reco = 'tos' then 'Cross-sell' 
		when reco = 'lwc' then 'Cross-sell' 
		when reco = 'hp' then 'Cross-sell' 
		when reco = 'wfp' then 'Cross-sell' 
		when reco = 'whsia' then 'Cross-sell' 
		when reco = 'tos_c' then 'Cross-sell' 
		when reco = 'tos_u' then 'Cross-sell' 
		end as category,
		case 
		when reco = 'hsic' then 'Internet'  
		when reco = 'ht' then 'Internet + Optik' 
		when reco = 'hs' then 'Internet + SHS' 
		when reco = 'hts' then 'Internet + Optik + SHS' 
		when reco = 'shs' then 'SHS' 
		when reco = 'tv' then 'Optik' 
		when reco = 'sws' then 'SWS' 
		when reco = 'tos' then 'TOS' 
		when reco = 'lwc' then 'LWC' 
		when reco = 'hp' then 'HP' 
		when reco = 'wfp' then 'WFP' 
		when reco = 'whsia' then 'WHSIA' 
		when reco = 'tos_c' then 'TOS - Complete' 
		when reco = 'tos_u' then 'TOS - Ultimate' 
		end as subcategory

		from nba_offer_targeting.nba_ffh_model_scores_prospects a 
		inner join mob_ban_lpds_id b 
		on cast(a.lpds_id as string) = cast(b.lpds_id as string)
	),

	casa as (
		-- Home Solutions customers in casa that called Telus in the last 90 days that dealt with the offer (or eligible for the offers)
		SELECT  
		evar247_txt AS ban, 
		REPLACE (eVar223_txt,':',',') AS offer_id,
		CASE WHEN eVar224_txt = 'Not interested' or eVar224_txt = 'Pas intéresséd' THEN 1 ELSE 0 END AS not_interested_casa,
		CASE WHEN eVar224_txt = 'Highly interested' or eVar224_txt = 'Très intéressé' THEN 1 ELSE 0 END AS highly_interested_casa
		FROM `cio-datahub-enterprise-pr-183a.ent_cust_intractn.bq_casa_event` casa
		WHERE DATE_DIFF(current_date(), DATE(casa_event_ts), DAY) <= 90
		AND eVar224_txt IS NOT NULL
		AND evar247_txt IS NOT NULL
		AND CHAR_LENGTH(eVar223_txt) >= 19 
		AND lower(evar131_txt) = 'mobility'
	),

	casa_feedback as (
		select ban
		, offer_id
		, max(not_interested_casa) as not_interested_casa
		, max(highly_interested_casa) as highly_interested_casa
		from casa 
		group by 1, 2 
	), 


	digital as (
		-- Home Solutions customers that visited Telus digital in the last 90 days that shown interests in the offers (or eligible for the offers)
		SELECT t1.clickstream_event_date,
		REPLACE(t1.offer_id,':',',') AS offer_id,
		t1.un_bacct_bus_bacct_num as ban,
		CASE WHEN 
		((offer_click_ind != TRUE OR offer_click_ind IS NULL) AND (offer_conversion_ind != TRUE OR offer_conversion_ind IS NULL) AND DATE_DIFF(CURRENT_DATE(), DATE(clickstream_event_date), DAY) > 7)
		OR
		(offer_click_ind = TRUE AND (offer_conversion_ind != TRUE OR offer_conversion_ind IS NULL) AND DATE_DIFF(CURRENT_DATE(), DATE(clickstream_event_date), DAY) > 3)
		THEN 1 ELSE 0 END AS not_interested_digital
		FROM  `dq-build-dsc-dev-682e3a.dq_workspace.nba_report_r5` t1
		LEFT JOIN `dq-build-dsc-dev-682e3a.dq_workspace.nba_offers_tbl` t3
		ON CAST(t1.offer_id AS STRING)=CAST(t3.Promo_IDs AS STRING)
		WHERE
		lower(t1.offer_type) = 'home solutions'
		AND un_bacct_bus_bacct_num IS NOT NULL
		AND LENGTH(t1.offer_id)>=19 
		AND DATE_DIFF(CURRENT_DATE(), t1.clickstream_event_date, DAY) <= 90 
		AND (offer_impression_ind IS NOT NULL OR offer_click_ind IS NOT NULL OR offer_conversion_ind IS NOT NULL)
	), 

	digital_feedback as (
		select offer_id
		, ban
		, max(not_interested_digital) as not_interested_digital 
		from digital
		group by 1, 2
	), 

	ranking1 as (
		select distinct a.ban
		, a.lpds_id
		, a.candate
		, a.Category
		, a.Subcategory
		, a.digital_category
		, a.promo_seg
		, a.offer_code
		, a.ASSMT_VALID_START_TS
		, a.ASSMT_VALID_END_TS
		, a.rk
		, CAST(1 + RAND() * 10 AS INT64) as rk2
		, b.nba_ranking
		, c.not_interested_casa
		, c.highly_interested_casa
		, d.not_interested_digital
		, e.offer_ranking
		from nba_offer_targeting.qua_base_mob a 
		left join nba_ranking b
		on a.ban = b.ban  and a.lpds_id = cast(b.lpds_id as int64) and trim(a.Category) = trim(b.category) and trim(a.Subcategory) = trim(b.subcategory)
		left join casa_feedback c
		on cast(a.ban as int) = cast(c.ban as int) and a.offer_code = c.offer_id
		left join digital_feedback d
		on cast(a.ban as int) = cast(d.ban as int) and  a.offer_code = d.offer_id
		left join nba_offer_targeting.offer_ranking e
		on trim(a.Category) = trim(e.Category) and trim(a.Subcategory) = trim(e.Subcategory)
	),

	ranking2 as (
		select *
		-- , row_number() over (partition by ban, lpds_id, category, subcategory order by rk2) as row_num
		, case 	when Category = 'Cross-sell' and Subcategory like 'TOS%' then row_number() over (partition by cust_id, lpds_id, category, left(subcategory, 3) order by nba_ranking, rk2) 
				else 1
		  end as row_num
		, case  when highly_interested_casa = 1 then 0
				when not_interested_casa = 1 or  not_interested_digital = 1 then 999
				when not_interested_casa = 1 and not_interested_digital = 1 then 9999
				when nba_ranking is null then 99
				else nba_ranking
		  end as ad_nba_ranking
		from ranking1
	)

	select null as cust_id
	, ban as mobility_ban
	, lpds_id
	, promo_seg
	, offer_code
	, rank() over (partition by ban, lpds_id order by ad_nba_ranking ,offer_ranking, rk2, candate) as ranking
	, digital_category
	, assmt_valid_start_ts
	, assmt_valid_end_ts
	from ranking2
	where row_num = 1
	order by ban
	, ranking
	; 
	
END
;

CALL nba_offer_targeting.bq_sp_nba_ffh_offer_ranking_prospects()




