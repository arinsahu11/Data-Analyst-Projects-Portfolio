-- Q15 Top 5 doctors who generated the most revenue but had the fewest patients
SELECT
Doctor_Name,
COUNT(DISTINCT patient_id) AS patient_count,
SUM(Total_Bill) AS total_revenue
FROM er_doctor
GROUP BY Doctor_Name
ORDER BY
SUM(Total_Bill) DESC,
COUNT(DISTINCT patient_id) ASC
LIMIT 5;


-- Q16 Department where average waiting time has decreased over three consecutive months
SELECT DISTINCT department_referral
FROM (
SELECT
department_referral,
YEAR(visit_date) AS year,
MONTH(visit_date) AS month,
AVG(patient_waittime) AS avg_wait_time,
LAG(AVG(patient_waittime), 1) OVER (
PARTITION BY department_referral
ORDER BY YEAR(visit_date), MONTH(visit_date)
) AS last_month_wait,
LAG(AVG(patient_waittime), 2) OVER (
PARTITION BY department_referral
ORDER BY YEAR(visit_date), MONTH(visit_date)
) AS two_months_ago_wait
FROM er_patients
GROUP BY department_referral, year, month
) wait_data
WHERE two_months_ago_wait IS NOT NULL
AND avg_wait_time < last_month_wait
AND last_month_wait < two_months_ago_wait;


-- Q17 Ratio of male to female patients per doctor, ranked by ratio
SELECT
d.Doctor_Name,
COUNT(CASE WHEN p.patient_gender = 'Male' THEN 1 END) AS male_count,
COUNT(CASE WHEN p.patient_gender = 'Female' THEN 1 END) AS female_count,
ROUND(
	COUNT(CASE WHEN p.patient_gender = 'Male' THEN 1 END) * 1.0 /
	NULLIF(COUNT(CASE WHEN p.patient_gender = 'Female' THEN 1 END), 0),
        2
) AS male_female_ratio
FROM er_doctor d
JOIN er_patients p ON d.patient_id = p.patient_id
GROUP BY d.Doctor_Name
ORDER BY male_female_ratio DESC;


-- Q18 Average satisfaction score of patients per doctor
SELECT
d.Doctor_Name,
ROUND(AVG(p.patient_sat_score), 2) AS avg_satisfaction
FROM er_doctor d
JOIN er_patients p ON d.patient_id = p.patient_id
GROUP BY d.Doctor_Name
ORDER BY avg_satisfaction DESC;


-- Q19 Doctors who treated patients from different races (diversity count)
SELECT
d.Doctor_Name,
COUNT(DISTINCT p.patient_race) AS race_diversity
FROM er_doctor d
JOIN er_patients p ON d.patient_id = p.patient_id
GROUP BY d.Doctor_Name
ORDER BY race_diversity DESC;


-- Q20 Ratio of total bills (male to female) per department
SELECT
d.department_referral,
ROUND(
SUM(d.Total_Bill * (p.patient_gender = 'Male')) /
NULLIF(SUM(d.Total_Bill * (p.patient_gender = 'Female')), 0),
2
) AS male_female_bill_ratio
FROM er_doctor d
JOIN er_patients p ON d.patient_id = p.patient_id
GROUP BY d.department_referral;


-- Q21
UPDATE er_patients
SET patient_sat_score =
CASE
WHEN patient_sat_score + 2 > 10 THEN 10
ELSE patient_sat_score + 2
END
WHERE department_referral = 'General Practice'
AND patient_waittime > 30;




