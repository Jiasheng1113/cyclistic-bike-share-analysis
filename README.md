# Cyclistic Bike-Share Case Study: Uncovering Seasonal & Weather Drivers for Ridership

##  Executive Summary
This case study analyzes historical trip data from Cyclistic, a fictional bike-share company, to understand how casual riders and annual members use the service differently. By blending trip logs with granular meteorological data (temperature and daylight hours), this project uncovers critical seasonal behaviors. 

The core breakthrough reveals that **temperature variations, rather than daylight duration, act as the primary behavioral catalyst** for ridership spikes—particularly within the casual rider segment. These insights provide a data-driven foundation for targeting high-value conversion marketing campaigns.

PowerBI link
https://app.powerbi.com/view?r=eyJrIjoiOWI3MTVhMTAtM2Q0Yy00ZDhjLTg4YjYtNWE0YzQxZWZjOTNlIiwidCI6IjBjOTBiZjlhLTU0ZWItNDlhMi1iOTkwLTI4ZWIxNGU1MTlkMiJ9&pageName=33f642ee0490a5e23d60
---

##  The Data Toolkit
* **Data Extraction & Aggregation:** SQL (PostgreSQL) - Dbeaver, pgAdmin
* **Data Modeling & Visualization:** Power BI Desktop
* **Statistical Analysis:** DAX (Data Analysis Expressions), SQL (PostgreSQL)

---

## Business Task & Hypothesis
**Objective:** Analyze how weather patterns affect casual vs. member ridership volumes to maximize annual membership conversions.

* **Initial Hypothesis:**
* 1) Total monthly ridership is strictly correlated with daylight duration (longer summer days = more trips).
* 2) Casual riders aren't using these bikes to get to work. They are overwhelmingly weekend users.
* **The Reality Check:** While daylight has a positive correlation, advanced scatter plot and regression analysis proves that **average monthly temperature ($^\circ$C)** holds a significantly stronger statistical relationship with casual rider behavior.

---
##  Data Cleaning & Manipulation Documentation
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
### 3. Data Transformation Summary Table
After executing the cleaning script, the dataset structure shifted as follows:
| Metric | Before Cleaning | After Cleaning | Net Change / Reason |
| :--- | :--- | :--- | :--- |
| **Total Row Count** | 5,681,500 | 5,681,475 | -35 rows (Removed duplicated) |
| **Total Column Count** | 13 | 16 | +3 columns (start_region, is_valid_trip,trip_duration) |
| **Data Integrity** | Raw / Unfiltered | Verified & Structured | Ready for summary metrics and visualization |

## Dashboard Structure & Strategic Insights

### Page 1: Executive Summary & Temporal Habits
*   **Visuals:** KPI Summary Cards, Clustered Column Chart (Trip Volumes), Avg Trip Duration Card.
*   **Data Findings:** Annual members dominate weekdays (**70% of total weekday rides**) for fast, routine commutes. Casual riders surge heavily on weekends, matching member volumes at nearly a **50% split**.
*   **Behavioral Proxy:** Members average a crisp **13 minutes** per trip, while casual riders keep bikes out **54% longer (20 minutes average)**, proving their intent is purely recreational.
*   **Strategy:** Target heavy weekend casual riders with a **"Weekday Commuter Pass"** trial (5 free morning rush-hour rides) to prove the utility of daily biking for work or university.

### Page 2: Environmental, Seasonal & Spatial Deep-Dive
*   **Visuals:** Stacked Area Chart (Q1–Q4 trends), Scatter Plots (Daylight vs. Temp), Regional Clustered Bar Chart.
*   **Data Findings (Weather):** Total demand drops by **78%** in **Q1 (Winter)** down to 467k rides, where casual ridership vanishes to just 19.47%. Conversely, demand peaks massively in **Q3 (Summer)** at **2.16 Million rides**, driving casual market share to its yearly maximum of **42.09%**. Advanced DAX statistical measures ($R$-scores) confirm outdoor temperature is a near-perfect linear driver of casual ride volume.
*   **Data Findings (Geography):** 
    *   **Central Region ("The Mega Hub"):** The main economic engine handling **4.7M total trips** (includes a massive **1.7M casual trips**).
    *   **South Region ("The Casual Outpost"):** The only region where casual riders outnumber annual members (**55.73%**), signifying a pure leisure/tourist hotspot.
*   **Strategy (Weather-Triggered):** Run targeted app promotions during late Q2 and Q3. When the local weekend forecast reaches a warm **20°C - 24°C**, push a dynamic update: *"Enjoying the sun? Lock in unlimited summer rides today by upgrading to an annual member!"*
*   **Strategy (Spatial):** Create a brand new contract tier: **"The Cyclistic Leisure Membership."** This pass offers an extended **45-to-60 minute ride limit** active on weekends. Advertise this tier directly via Out-of-Home (OOH) billboards at the physical bike docks in the Central and South regions to capture leisure riders who traditionally avoid the strict 30-minute commuter caps.

## Advanced Analysis & Statistical Proof
### 1） Visual and SQL query for the proportion
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

### Strategic Data Insights

By analyzing the distribution and proportions of rides across temporal categories, two distinct user personas emerge:

* **1. Annual Members dominate the Weekdays (Commuter Behavior):**
  * On weekdays, the majority of the users is annual member as 70% of users are annual members in weekdays. 
  * **Insight:** Annual members rely on Cyclistic as a highly stable, daily utility—likely for commuting to work or university, or connecting to public transit routes during rush hours.

* **2. Casual Riders dominate the Weekends (Leisure Behavior):**
  * On weekends, the proportion of casual riders increases significantly that almost goes to 50% on weekends. 
  * **Insight:** Casual users view Cyclistic primarily as a leisure, recreation, or tourist activity. They utilize the bikes when they have free time rather than for structured routines.

### Supporting Data Metrics (Ride Length vs. User Type)
To verify the leisure vs. commuter theories, the average trip duration was analyzed across both user segments:
* **Annual Members:** Average ride duration is **13 minutes** (Short, fast, routine-driven).
* **Casual Riders:** Average ride duration is **20 minutes** (Long, extended, leisure-driven).

Data Validation Note: Casual riders keep bikes out for roughly 54% longer per trip than members. Because annual memberships often penalize rides exceeding 30–45 minutes with overage fees, members optimize for efficiency. Casual riders, utilizing single-ride or day passes, display no time-sensitivity, reinforcing their recreational intent.

---
### 2. Seasonal Volume Dynamics

The analysis of the volume trips group by season has been done that using the query and visualise the data.
```sql
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
FROM cyclistic_trips_cleaned
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
```
<table>
  <thead>
    <tr>
      <th>Quarter (Season)</th>
      <th>User Type</th>
      <th>Percentage (%)</th>
      <th>Rides by Type</th>
      <th>Total Seasonal Rides</th>
    </tr>
  </thead>
  <tbody>
    <!-- Q1 -->
    <tr>
      <td rowspan="2">Q1 (Winter)</td>
      <td>casual</td>
      <td align="center">19.47%</td>
      <td align="right">91,040</td>
      <td rowspan="2" align="right"><strong>467,509</strong></td>
    </tr>
    <tr>
      <td>member</td>
      <td align="center">80.53%</td>
      <td align="right">376,469</td>
    </tr>
    <!-- Q2 -->
    <tr>
      <td rowspan="2">Q2 (Spring)</td>
      <td>casual</td>
      <td align="center">32.46%</td>
      <td align="right">447,672</td>
      <td rowspan="2" align="right"><strong>1,379,292</strong></td>
    </tr>
    <tr>
      <td>member</td>
      <td align="center">67.54%</td>
      <td align="right">931,620</td>
    </tr>
    <!-- Q3 -->
    <tr>
      <td rowspan="2">Q3 (Summer)</td>
      <td>casual</td>
      <td align="center">42.09%</td>
      <td align="right">910,611</td>
      <td rowspan="2" align="right"><strong>2,163,660</strong></td>
    </tr>
    <tr>
      <td>member</td>
      <td align="center">57.91%</td>
      <td align="right">1,253,049</td>
    </tr>
    <!-- Q4 -->
    <tr>
      <td rowspan="2">Q4 (Autumn)</td>
      <td>casual</td>
      <td align="center">33.75%</td>
      <td align="right">564,010</td>
      <td rowspan="2" align="right"><strong>1,671,014</strong></td>
    </tr>
    <tr>
      <td>member</td>
      <td align="center">66.25%</td>
      <td align="right">1,107,004</td>
    </tr>
  </tbody>
</table>
<img width="791" height="391" alt="Screenshot 2026-07-12 151347" src="https://github.com/user-attachments/assets/f05c094a-bd1c-4088-aebd-d764fae4d0da" />

### Strategic Data Insights
The Summer Surge (Q3 Peak): Q3 (Summer) represents the absolute peak demand for the entire year, handling over 2.16 million total rides. Crucially, this seasonal expansion is driven heavily by casual riders, whose market share jumps to its yearly maximum of 42.09%.

The Winter Freeze (Q1 Slump): Total demand bottoms out severely in Q1 (Winter), falling to just 467k rides (a ~78% drop from summer). Casual ridership vanishes almost entirely, plummeting down to 19.47% of the mix.

The Transition Curve: As seen in the stacked area chart, casual user activity begins climbing steadily in Spring (Q2), peaks during Summer (Q3), begins cooling down through Autumn (Q4), and collapses rapidly as winter weather sets in.

---
### 3. Correlation of the cyclistic trips
When visualized side-by-side on the dashboard, the data points reveal two completely different stories:
* **Trips vs. Daylight:** High data dispersion. Months with identical daylight profiles yield drastically different trip totals.
* **Trips vs. Temperature:** Extremely low dispersion. Data points form a tight, upward linear staircase, proving high predictability.

<img width="668" height="412" alt="Screenshot 2026-07-09 212753" src="https://github.com/user-attachments/assets/1bbd7f68-d3a4-43dc-baa4-cee44d046c02" />

### Mathematical Proof via DAX Correlation Coefficients
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
```
### Strategic Data Insights
Refer to the visualisation and correlation, the overall temperature correlation is better than daylight correlation. And we can see that the temperature is more likely is the causation to affected the trips that most higher temperature (maximum 24C for the study), the higher trips.
<img width="646" height="312" alt="Screenshot 2026-07-09 214947" src="https://github.com/user-attachments/assets/2e10a28e-beb6-4b05-bf43-6b628223f521" />

Temperature is the Primary Catalyst: The mathematical output confirms a near-perfect positive correlation between outdoor temperature and riding activity (achieving an $R$-score near the maximum limit).The Behavior Mechanism: Warmer outdoor temperatures (peaking around 24°C in this study) serve as a direct operational catalyst. While members maintain a baseline volume for necessary work commutes, casual ridership is highly volatile and bound tightly to weather comfort, making temperature the ultimate predictor of seasonal revenue changes.

---
### 4. Spatial Analysis: Regional Demand & User Hubs

To optimize marketing spend and physical bike distribution, a geographical analysis was conducted across five distinct operating regions. The data reveals highly contrasting behavioral hubs between casual riders and annual members:
<img width="543" height="210" alt="Screenshot 2026-07-13 221758" src="https://github.com/user-attachments/assets/5bcee4b7-d744-4457-a379-a23de1d6f538" />

| Region | User Type | Total Trips | Proportion (%) |
| :--- | :--- | :---: | :---: |
| **Central Region** | casual <br> member | 1,707,637 <br> 3,086,148 | 35.62% <br> **64.38%** |
| **East Region** | casual <br> member | 45,812 <br> 102,811 | 30.82% <br> **69.18%** |
| **North Region** | casual <br> member | 232,768 <br> 453,661 | 33.91% <br> **66.09%** |
| **South Region** | casual <br> member | 15,652 <br> 12,432 | **55.73%** <br> 44.27% |
| **West Region** | casual <br> member | 11,464 <br> 13,090 | 46.69% <br> 53.31% |


#### Key Geographical Insights

*   **The Central Region ("The Mega Hub"):** Accounting for over **4.7 Million total trips**, this region is the primary economic engine of Cyclistic's network. It is heavily dominated by annual members (**64.38%**), confirming its utility as a high-density commercial and transit core where users rely on bikes for daily workplace or university commuting.
*   **The South Region ("The Casual Outpost"):** The South stands out as a clear operational anomaly—it is the **only region** where casual riders outnumber annual members (**55.73%** vs. 44.27%). Due to its lower trip volume and higher casual ratio, this zone represents a dedicated recreational hotspot (e.g., parks, scenic coastal pathways, or tourist attractions).
*   **North and East Regions ("The Commuter Strongholds"):** These suburban sectors yield the highest concentrations of annual members (**66.09%** and **69.18%** respectively). This strongly indicates that residents in the North and East utilize Cyclistic as a structured "first-mile/last-mile" transit solution to bridge the gap between their homes and local train stations.


