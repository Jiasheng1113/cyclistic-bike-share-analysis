-- Create Table to import
CREATE TABLE cyclistic_table (
    ride_id VARCHAR(255),
    rideable_type VARCHAR(50),
    started_at TIMESTAMP,
    ended_at TIMESTAMP,
    start_station_name VARCHAR(255),
    start_station_id VARCHAR(255),
    end_station_name VARCHAR(255),
    end_station_id VARCHAR(255),
    start_lat DECIMAL,
    start_lng DECIMAL,
    end_lat DECIMAL,
    end_lng DECIMAL,
    member_casual VARCHAR(50)
);

-- To import
COPY cyclistic_table
FROM 'file path' WITH CSV HEADER;

-- Remove Duplicated data
COPY cyclistic_table
FROM 'file path' WITH CSV HEADER
WHERE EXTRACT(MONTH FROM started_at) <> 4;

-- Create another table for analysis table
CREATE TABLE cyclistic_trips_cleaned_table AS
SELECT 
	*,
	
	-- 1. CALCULATE TRIP DURATION (with DST adjustments) - (ref 2.4)
	ROUND((EXTRACT(EPOCH FROM (ended_at - started_at)) / 60
	+ CASE 
		WHEN started_at > ended_at THEN 60 
		WHEN DATE(started_at) = '2026-03-08'
			AND started_at < '2026-03-08 02:00:00'
			AND ended_at >= '2026-03-08 03:00:00' THEN -60 
		ELSE 0 
	  END)::numeric, 2) AS trip_duration,

	-- 2. FILTER VALID TRIPS (Flag out tests, maintenance, and outliers) - (ref 2.3)
	CASE 
		WHEN EXTRACT(EPOCH FROM (ended_at - started_at)) / 60 < 1 THEN 0
		WHEN EXTRACT(EPOCH FROM (ended_at - started_at)) / 60 > 1440 THEN 0
		WHEN LOWER(start_station_name) LIKE '%test%' 
			OR LOWER(start_station_name) LIKE '%warehouse%' 
			OR LOWER(start_station_name) LIKE '%hq%' 
			OR LOWER(end_station_name) LIKE '%test%' 
			OR LOWER(end_station_name) LIKE '%warehouse%' 
			OR LOWER(end_station_name) LIKE '%hq%' THEN 0
		ELSE 1 
	END AS is_valid_trip,

	-- 3. CATEGORIZE REGIONS BASED ON COORDINATES - (ref 2.2)
	CASE
		WHEN start_lng < -87.75 THEN 'West Region'
		WHEN start_lat > 41.95 AND start_lng >= -87.75 THEN 'North Region'
		WHEN start_lat < 41.78 AND start_lng >= -87.75 THEN 'South Region'
		WHEN start_lat BETWEEN 41.85 AND 41.95 AND start_lng BETWEEN -87.68 AND -87.60 THEN 'Central Region'
		WHEN start_lng > -87.60 THEN 'East Region'
		ELSE 'Central Region'
	END AS start_region

FROM cyclistic_table;

-- Visual and SQL query for the proportion
SELECT
	member_casual,
	CASE 
		WHEN (EXTRACT(ISODOW FROM ended_at) BETWEEN 1 AND 5) THEN 'Weekday'
		WHEN (EXTRACT(ISODOW FROM ended_at) BETWEEN 6 AND 7) THEN 'Weekend'
	END AS Temporal_categories,	
	COUNT(*) AS total_trips,
	round(COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY CASE 
		WHEN (EXTRACT(ISODOW FROM ended_at) BETWEEN 1 AND 5) THEN 'Weekday'
		WHEN (EXTRACT(ISODOW FROM ended_at) BETWEEN 6 AND 7) THEN 'Weekend'
	END) * 100,2) AS rate
FROM cyclistic_trips_cleaned_table 
WHERE is_valid_trip = 1
GROUP BY member_casual, Temporal_categories;

-- Seasonal Volume Dynamics

SELECT
    member_casual,
    CASE 
        WHEN EXTRACT(MONTH FROM ended_at) IN (12, 1, 2) THEN 'Q1 (Winter)'
        WHEN EXTRACT(MONTH FROM ended_at) IN (3, 4, 5) THEN 'Q2 (Spring)'
        WHEN EXTRACT(MONTH FROM ended_at) IN (6, 7, 8) THEN 'Q3 (Summer)'
        WHEN EXTRACT(MONTH FROM ended_at) IN (9, 10, 11) THEN 'Q4 (Autumn)'
        ELSE 'Unknown'
    END AS season,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY CASE 
        WHEN EXTRACT(MONTH FROM ended_at) IN (12, 1, 2) THEN 'Q1 (Winter)'
        WHEN EXTRACT(MONTH FROM ended_at) IN (3, 4, 5) THEN 'Q2 (Spring)'
        WHEN EXTRACT(MONTH FROM ended_at) IN (6, 7, 8) THEN 'Q3 (Summer)'
        WHEN EXTRACT(MONTH FROM ended_at) IN (9, 10, 11) THEN 'Q4 (Autumn)'
        ELSE 'Unknown'
    END ), 2) AS rate,
    COUNT(*)
FROM cyclistic_trips_cleaned_table
WHERE is_valid_trip = 1 -- And here
GROUP BY 
    member_casual,
    CASE 
        WHEN EXTRACT(MONTH FROM ended_at) IN (12, 1, 2) THEN 'Q1 (Winter)'
        WHEN EXTRACT(MONTH FROM ended_at) IN (3, 4, 5) THEN 'Q2 (Spring)'
        WHEN EXTRACT(MONTH FROM ended_at) IN (6, 7, 8) THEN 'Q3 (Summer)'
        WHEN EXTRACT(MONTH FROM ended_at) IN (9, 10, 11) THEN 'Q4 (Autumn)'
        ELSE 'Unknown'
    END ;

--  Spatial Analysis: Regional Demand & User Hubs
 SELECT 
    start_region,
    member_casual AS user_type,
    COUNT(*) AS total_trips,
    ROUND(COUNT(*) / SUM(COUNT(*)) OVER(PARTITION BY start_region) * 100, 2) AS regional_proportion
FROM cyclistic_trips_cleaned_table
WHERE is_valid_trip = 1 AND start_region IS NOT NULL
GROUP BY start_region, member_casual
ORDER BY start_region, user_type;
