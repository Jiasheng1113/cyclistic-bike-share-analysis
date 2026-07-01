# Cyclistic Bike-Share Case Study: Uncovering Seasonal & Weather Drivers for Ridership

## 📌 Executive Summary
This case study analyzes historical trip data from Cyclistic, a fictional bike-share company, to understand how casual riders and annual members use the service differently. By blending trip logs with granular meteorological data (temperature and daylight hours), this project uncovers critical seasonal behaviors. 

The core breakthrough reveals that **temperature variations, rather than daylight duration, act as the primary behavioral catalyst** for ridership spikes—particularly within the casual rider segment. These insights provide a data-driven foundation for targeting high-value conversion marketing campaigns.

PowerBI link
https://app.powerbi.com/view?r=eyJrIjoiOWI3MTVhMTAtM2Q0Yy00ZDhjLTg4YjYtNWE0YzQxZWZjOTNlIiwidCI6IjBjOTBiZjlhLTU0ZWItNDlhMi1iOTkwLTI4ZWIxNGU1MTlkMiJ9
---

## 🛠️ The Data Toolkit
* **Data Extraction & Aggregation:** SQL (PostgreSQL)
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
FROM cyclistic_trips_cleaned ctc 
WHERE is_valid_trip = 1
GROUP BY member_casual, Temporal_categories;
```
The visualisation have been perform for bulid the clustered column chart and 100% stacked column chart.
<img width="530" height="259" alt="Screenshot 2026-07-01 223101" src="https://github.com/user-attachments/assets/9fc6a809-fb68-48a0-aee9-d31f5da5dcd7" />

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
