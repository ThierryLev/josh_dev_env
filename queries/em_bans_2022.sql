
CREATE OR REPLACE TABLE `divg-josh-pr-d1cc3a.campaign_performance_analysis.em_bans_2022` 

AS

SELECT PARSE_DATE("%d-%b-%y", CONCAT(LEFT(CAMP_INHOME, 2), "-", SUBSTRING(CAMP_INHOME, 3, 3), "-", SUBSTRING(CAMP_INHOME, 8, 2))) as CAMP_INHOME
,CAMP_ID	
,CAMP_CONTACT	
,CAMP_FILE	
,CAMP_TEST	
,CUST_ID	
,BACCT_NUM
,TELENO	
,CAMP_EMAIL	
,DELIVERED
,OPENED	
,CLICKTHROUGH
,SOFTBOUNCE	
,HARDBOUNCE				
,UNSUBSCRIBE	

FROM `divg-churn-analysis-pr-7e40f6.SAStoGCP.ad_hoc_230221`






