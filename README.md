# Cyclistic Bike-Share Case Study: Uncovering Seasonal & Weather Drivers for Ridership

## 📌 Executive Summary
This case study analyzes historical trip data from Cyclistic, a fictional bike-share company, to understand how casual riders and annual members use the service differently. By blending trip logs with granular meteorological data (temperature and daylight hours), this project uncovers critical seasonal behaviors. 

The core breakthrough reveals that **temperature variations, rather than daylight duration, act as the primary behavioral catalyst** for ridership spikes—particularly within the casual rider segment. These insights provide a data-driven foundation for targeting high-value conversion marketing campaigns.

PowerBI link
https://app.powerbi.com/view?r=eyJrIjoiOWI3MTVhMTAtM2Q0Yy00ZDhjLTg4YjYtNWE0YzQxZWZjOTNlIiwidCI6IjBjOTBiZjlhLTU0ZWItNDlhMi1iOTkwLTI4ZWIxNGU1MTlkMiJ9&pageName=33f642ee0490a5e23d60
---

## 🛠️ The Data Toolkit
* **Data Extraction & Aggregation:** SQL (PostgreSQL) - Dbeaver, pgAdmin
* **Data Modeling & Visualization:** Power BI Desktop
* **Statistical Analysis:** DAX (Data Analysis Expressions), SQL (PostgreSQL)

---

## 📊 Business Task & Hypothesis
**Objective:** Analyze how weather patterns affect casual vs. member ridership volumes to maximize annual membership conversions.

* **Initial Hypothesis:**
* 1) Total monthly ridership is strictly correlated with daylight duration (longer summer days = more trips).
* 2) Casual riders aren't using these bikes to get to work. They are overwhelmingly weekend users.
* **The Reality Check:** While daylight has a positive correlation, advanced scatter plot and regression analysis proves that **average monthly temperature ($^\circ$C)** holds a significantly stronger statistical relationship with casual rider behavior.

---
## 🧹 Data Cleaning & Manipulation Documentation
### 1) Data Stacking & Initial Verification

Before performing any cleaning, the 12 separate monthly CSV files from the Cyclistic trip history system were audited. I verified that all files contained identical column names and data types. And importing the 12 file to the PostgreSQL by using pgAdmin to do the data cleaning. Below is the step to import:
1) Create table in the SQL by using below query
```sql
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
```
2) to import the file 12 times each months

```sql
COPY cyclistic_table
FROM 'file path' WITH CSV HEADER;
```

### 2) Cleaning and Manipulation Log

#### 2.1 Duplicated data
* **Discovery**: The April 2026 and May 2026 datasets contained duplicate records due to an error in Cyclistic's source CSV files. The April file extracted records using the ended_at column, whereas the May file used the started_at column. This inconsistency caused data overlapping and led to import failures for the May 2026 dataset until it was cleaned.
* **Action**: To import May'26 data with using the where function to filter out the April data as below - 
```sql
COPY cyclistic_table
FROM 'file path' WITH CSV HEADER
WHERE EXTRACT(MONTH FROM started_at) <> 4;
```
* **Justification**: Using a staging filter rather than permanently altering or manually deleting rows from the source file preserves data lineage and ensures the cleaning process is programmatic, repeatable, and less prone to human error.

#### 2.2 Addressing Missing Station and Coordinate Data (Missing Data Strategy)
* **Discovery**: I discovered that approximately 20% of the dataset contained location gaps, split into two distinct situations: rows missing only station text fields (start_station_name/end_station_name), and rows missing both station names and numerical coordinates (end_lat/end_lng)..and over 70% of the entries are completely missing station names, station IDs, and precise coordinates, or are corrupted down to an unusable 2-decimal-place precision. However, the core behavioral fields (started_at, ended_at, and member_casual) remain 100% intact and uncorrupted during this same period.
* **Action**: No deletion actions were implemented. To preserve data integrity and maintain exact tracking capabilities, a two-part conditional strategy was applied:
    * For records where numerical coordinates were completely missing, the fields were intentionally left as system `NULL` values rather than forcing text placeholders or artificial dummy numbers (like `0.0`) into them.
    * Implemented Feature Engineering to classify raw geographic coordinates (started_lat, started_lng) into cardinal direction regions (e.g east region, west region, etc.). This reduced categorical complexity and allowed for 100% data utilization.
* **Justification**: Deleting these rows would ruin our total trip volume calculations. The missing text fields simply indicate dockless bike usage, which is resolved by classify raw geographic coordinates into cardinal direction regions. Leaving missing coordinate numbers as `NULL` prevents database system crashes while ensuring mapping software (like Tableau) automatically skips plotting rows that have no spatial data, preventing errors like "Null Island" artifacts.

#### 2.3 Data Invalidation & Outlier Management
* **Discovery**: During the data profiling phase, three distinct types of data anomalies were identified:
	* **Trips Exceeding 24 Hours (>1,440 minutes)**: These represent system errors, docking issues, or lost/stolen assets where the session remained open indefinitely.
	* **Trips Under 1 Minute (<60 seconds)**: These represent "false starts" where users unlocked a bike, noticed a mechanical issue (e.g., flat tire, broken seat), and immediately re-docked it at the same station.
	* **Operational Test Rides**: Internal quality control and logistics records identified by station names containing keywords like "HQ", "Warehouse", or "test".
* **Action**: Rather than permanently deleting raw records, an is_valid_trip column was engineered. A conditional CASE WHEN statement was used to dynamically flag valid rows as 1 and invalid system anomalies as 0 (ref 2.6).
* **Justification**: Isolating these anomalies is critical for data integrity. Excluding these outliers ensures that metrics like average ride duration and user trip counts reflect genuine customer behavior and prevent heavily skewed results.

#### 2.4 Time Travel Paradox
* **Discovery**: A data anomaly was identified where the ended_at timestamp occurred before the started_at timestamp, resulting in negative trip durations. This occurred on November 2, 2025, when Daylight Saving Time (DST) ended and clocks rolled back 1 hour. Conversely, on March 8, 2026, when DST started, clocks skipped forward 1 hour, causing an artificial 60-minute inflation in ride durations (e.g., a 17-minute ride appearing as 77 minutes).
* **Action**: To resolve these clock adjustments without falling into database timezone casting traps, an explicit CASE WHEN statement was integrated into the data cleaning view:
	1.	For the November Rollback: If ended_at < started_at, the script automatically adds 60 minutes to correct the negative duration.
	2.	For the March Skip Forward: If a ride crosses the non-existent 2:00 AM hour on March 8, 2026, the script automatically subtracts 60 minutes to eliminate the phantom hour.
	3.	Otherwise, the standard wall-clock duration math is preserved. 
* **Justification** : The raw timestamps are not errors; they show the actual wall-clock time when the bikes were unlocked and docked. Changing the raw source data is bad practice because it destroys the original project records.

#### 2.5 Create another table for analysis table
* **Discovery**: Directly altering or running update queries on the primary table poses a high risk of destroying or corrupting the original data if a query is written incorrectly.
* **Action**: Created a permanent, physical analytical table in PostgreSQL to house the newly engineered columns and transformations referenced in steps 2.2 through 2.4.
```sql
-- Just change this top part to create a physical table
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
```
* **Justification**: A physical analytical table (CREATE TABLE ... AS) was deployed rather than a dynamic SQL view to make the Power BI dashboard load much faster. By calculating the complex math—like Daylight Saving Time (DST) adjustments, text-pattern filters, and region bucketing—only once and saving it directly to a table, the database doesn't have to re-run heavy queries every time you click a chart. This separates the raw source material from the final polished data for analysis purposes, ensuring the original data stays safe and untouched.
---

## 🕵️‍♂️ Advanced Analysis & Statistical Proof
### Visual and SQL query for the proportion
When visualised the dashboard, we query the total trip from the SQL and group by member_casual, temporal_categories that seperate the day for weekday and weekend.
And also I performing calculate the proportion of the member_casual within the temporal_categories to know the behavior of the users.

```sql
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
```
The visualisation have been perform for bulid the clustered column chart and 100% stacked column chart.

<img width="791" height="355" alt="Screenshot 2026-07-01 223830" src="https://github.com/user-attachments/assets/99fad4ae-f9ed-4a3e-8c95-a3627b1b32c5" />

### 💡 Strategic Data Insights

By analyzing the distribution and proportions of rides across temporal categories, two distinct user personas emerge:

* **1. Annual Members dominate the Weekdays (Commuter Behavior):**
  * On weekdays, the majority of the users is annual member as 70% of users are annual members in weekdays. 
  * **Insight:** Annual members rely on Cyclistic as a highly stable, daily utility—likely for commuting to work or university, or connecting to public transit routes during rush hours.

* **2. Casual Riders dominate the Weekends (Leisure Behavior):**
  * On weekends, the proportion of casual riders increases significantly that almost goes to 50% on weekends. 
  * **Insight:** Casual users view Cyclistic primarily as a leisure, recreation, or tourist activity. They utilize the bikes when they have free time rather than for structured routines.

### 🔢 Supporting Data Metrics (Ride Length vs. User Type)
To verify the leisure vs. commuter theories, the average trip duration was analyzed across both user segments:
* **Annual Members:** Average ride duration is **13 minutes** (Short, fast, routine-driven).
* **Casual Riders:** Average ride duration is **20 minutes** (Long, extended, leisure-driven).

This data support confirms that casual riders keep the bikes out for twice as long as members, proving a recreational usage pattern.
---

### 🎯 Business Recommendations for Marketing Strategy
Based on these insights, a standard "one-size-fits-all" marketing campaign will not work. To convert casual weekend riders into long-term annual members, the business should try:

1. **Targeted Weekend Activation:** Introduce a "Weekend Commuter Pass" or digital marketing banners within the app during peak weekend hours, specifically highlighting how much money or time a user would save if they switched to an annual membership for their weekday travel.
2. **Seasonal Work/Campus Campaigns:** Run conversion campaigns at the start of the typical work or school semesters, targeting casual riders who have a history of taking multiple weekend trips, positioning annual membership as the ultimate weekday commuting hack.

### 1. Visual Proof (Scatter Plot Matrix)
When visualized side-by-side on the dashboard, the data points reveal two completely different stories:
* **Trips vs. Daylight:** High data dispersion. Months with identical daylight profiles yield drastically different trip totals.
* **Trips vs. Temperature:** Extremely low dispersion. Data points form a tight, upward linear staircase, proving high predictability.

`![Cyclistic Dashboard Scatter Plots](Insert_Link_To_Your_Dashboard_Screenshot_Here.png)`

### 2. Mathematical Proof via DAX Correlation Coefficients
To validate the visual findings, Pearson Correlation Coefficient ($R$) measures were built natively in Power BI to calculate relationship strengths on a scale of -1 to 1.

#### **Temperature Correlation Measure:**
```dax
Temperature Correlation = 
VAR SummaryTable = 
    ADDCOLUMNS(
        VALUES('cyclistic_trips_cleaned_202606281428'[month_name]),
        "MonthlyTrips", CALCULATE(SUM('cyclistic_trips_cleaned_202606281428'[count_trips])),
        "MonthlyTemp", CALCULATE(AVERAGE('Temperare'[C]))
    )
VAR MeanX = AVERAGEX(SummaryTable, [MonthlyTemp])
VAR MeanY = AVERAGEX(SummaryTable, [MonthlyTrips])
VAR Numerator = SUMX(SummaryTable, ([MonthlyTemp] - MeanX) * ([MonthlyTrips] - MeanY))
VAR Denominator = SQRT(SUMX(SummaryTable, ([MonthlyTemp] - MeanX)^2) * SUMX(SummaryTable, ([MonthlyTrips] - MeanY)^2))
RETURN
    DIVIDE(Numerator, Denominator)
