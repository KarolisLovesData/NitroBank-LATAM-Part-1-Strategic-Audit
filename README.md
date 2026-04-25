# NitroBank-LATAM-01-Strategic-Audit
**NOTE:** This is a comprehensive portfolio project utilizing a simulated enterprise dataset. The metrics, company names, and financial figures were constructed to demonstrate production-grade Analytics Engineering, Medallion Architecture, and business-focused data modeling.

### 📑 Table of Contents
* [Executive Summary](#executive-summary)
  * [Data Architecture & Scope](#data-architecture--scope)
  * [Audit Scale & Data Volume](#audit-scale--data-volume)
* [Part 1: Growth and Acquisition](#part-1-growth-and-acquisition)
* [Part 2: Unit Economics & Profitability](#part-2-unit-economics--profitability)
* [Part 3: Transaction Success & Friction Removal](#part-3-transaction-success--friction-removal)
* [🔧 Analytics Engineering & Architecture](#-analytics-engineering--architecture)

## Executive Summary

Commissioned by executive leadership, this three-part strategic audit evaluates the Latin American expansion of **NitroBank**, a rapidly scaling neobank currently serving **Brazil, Mexico, and Colombia**.

By analyzing over **1 million potential users** alongside **145K+** transactions from January 2024 to January 2026, this report moves past surface-level volume metrics to identify the technical roadblocks, hidden revenue engines, and product innovations required to actually dominate the LATAM fintech landscape.

The findings and recommended actions are structured across three core areas:

* **Part 1: Growth & Acquisition:** A diagnostic breakdown of our top-of-funnel conversion. We identified a massive **67% drop-off** at Document Submission and outlined a **$0 marketing-spend** opportunity to unlock explosive user growth by resolving technical KYC crashes.
* **Part 2: Unit Economics & Profitability:** An analysis of our "Profitability Paradox." We outline the strategy to shift acquisition focus away from low-margin volume and lean heavily into Mexico, our true economic engine boasting an elite **1.15% Take Rate**.
* **Part 3: Transaction Success & Friction Removal:** A deep dive into **>145k transactions** validating our market stability. We detail the blueprint to transform "Insufficient Funds" declines—which account for **89.2% of failures**—from a perceived risk into a highly profitable micro-credit product line.

**Strategic Imperative:** By repairing the KYC ingestion pipeline, pivoting acquisition spend to Mexico's high-yield segments, and monetizing declined transactions through instant micro-credit, NitroBank can immediately transition from a low-margin "digital wallet" into a highly profitable, full-service bank.

### 📊 The Executive Dashboard
*(A static view of the final metrics compiled from the Gold Layer. Click the image to view the full resolution).*

<a href="./Visuals/executive_dashboard.png" target="_blank">
  <img src="./Visuals/executive_dashboard.png" alt="Executive Dashboard" width="850">
</a>

### Data Architecture & Scope 

The audit was carried out following a **Medallion Architecture**. The Entity Relationship Diagram (ERD) below represents the **Silver Layer**, which serves as the cleaned, relational source of truth. Full **Medallion Transformation** flow and **Directed Acyclic Graph (DAG)** can be accessed in [🔧 Analytics Engineering & Architecture part.](#-analytics-engineering--architecture) 

<img src="./Visuals/ERD.png" alt="ERD" width="800"> 

### Audit Scale & Data Volume 

* **silver_events** (fact table): **1.62M+ web event records** processed (representing **1.05M unique users**), capturing detailed user interactions, device specifications, and marketing attribution.
* **silver_users** (dimension table): **450K+** unique registered accounts analyzed across all active regions to track onboarding and retention. 
* **silver_transactions** (fact table): **145K+** transaction records processed, tracking payment volume, approval rates, and decline triggers. 

***

# Part 1: Growth and Acquisition 

### The Divide: Elite Retention vs. Onboarding Failure 
**Stakeholder:** Head of Growth &nbsp;|&nbsp; **Priority:** 🔴 CRITICAL

**📊 Key Metrics:**
* **The KYC Wall:** 67% drop-off (~301,500 users) at Document Submission.
* **Elite Retention:** 90.3% of users fund their accounts once clearing the KYC wall.
* **Top-of-Funnel Contrast:** Colombia yields a 50.1% organic signup rate but only a 13.8% monetization rate, while "Unknown OS" traffic yields a staggering 26.8% monetization rate.

**The Insight:** NitroBank has exceptional product-market fit, but a single operational bottleneck is trapping massive revenue. The 67% KYC drop-off is practically identical across Brazil, Mexico, and Colombia, ruling out localized trust issues. With a heavily Android user base, this universal failure points to a severe technical crash (likely an Android Camera SDK loop) during document upload, artificially starving our user acquisition.
<br>**[Access SQL Queries](Analytics_Engineering/Part1_Gold_Layer_Funnel.sql)**
<br>

<img src="./Visuals/users_funnel.png" alt="Funnel" width="600"> 

**Strategic Action:**
1. **Technical Sprint:** Isolate KYC module timeouts and crashes by Device Model and Network Type to solve for LATAM's volatile mobile data environments.
2. **Incentive Restructuring:** Move the reward trigger from "KYC Completion" to "First Account Funding," replacing generic USD offers with psychologically substantial, localized tiers (e.g., 500 MXN, 50 BRL).
3. **Gated Recovery:** Deploy an A/B recovery campaign to the 301,500 "stuck" users *only* after confirming the SDK UI crashes are resolved.

**Business Impact:** Optimizing our onboarding to an industry-standard 60% completion rate triggers explosive bottom-up growth with **$0 in additional marketing spend.**

# Part 2: Unit Economics & Profitability 

### The Profitability Paradox & The "Trust Gap"
**Stakeholder:** CFO & Head of Strategy &nbsp;|&nbsp; **Priority:** 🟠 HIGH

**📊 Key Metrics:**
* **Total Payment Volume (TPV):** $56.3M processed globally.
* **The Engine (Mexico):** 1.15% Take Rate and $5.18 Average Revenue Per Active Customer (ARPAC).
* **The Trap (Colombia):** 0.50% Take Rate (lowest global margin).
* **The Trust Gap:** Mexican users exhibit a critical 60.8-hour Time-to-Value lag (2.5 days to first deposit).

**The Insight:** Volume does not inherently equal profit. While Colombia drives high user intent, scaling there will compress overall profit margins. Mexico is our true economic engine, processing less than half of Brazil's volume but generating significantly higher margins. However, Mexican users suffer a 2.5-day activation delay, proving they hesitate to deposit their first dollar until they have vetted the platform’s reliability.
<br>**[Access SQL Queries](Analytics_Engineering/Part_2.gold_fact_financials_monthly.sql)**
<br>

<img src="./Visuals/efficiency_heatmap.png" alt="Heatmap" width="600"> 

**Strategic Action:**
1. **Bridge the Trust Gap:** Launch a "Day 1 Funding Match" in Mexico (e.g., deposit $10, get $2) to pull forward initial deposits and collapse the 60.8-hour activation delay.
2. **Subsidize "The Whales":** Increase referral bonuses by 50%. The elite unit economics of this channel will easily absorb the higher CAC.
3. **Ring-Fence Ad Spend:** Shift paid marketing away from Colombia (moving to organic-led) and aggressively reallocate the Facebook Ad budget exclusively to Mexican acquisition to capture the $5.31 ARPAC.

**Business Impact:** Maximizes sustainable profit margins by pivoting Customer Acquisition Cost (CAC) directly toward high-LTV regions and high-value referral channels.

# Part 3: Transaction Success & Friction Removal 

### From Declines to Credit Revenue 
**Stakeholder:** Head of Product &nbsp;|&nbsp; **Priority:** 🟠 HIGH

**📊 Key Metrics:**
* **Approval Rate:** 89.36% in Mexico (mirroring Brazil/Colombia stability).
* **Decline Volume:** 15,296 total failed transactions.
* **The Liquidity Wall:** 89.2% of failures (13,649 transactions) were solely due to *Insufficient Funds*.

**The Insight:** High margins in Mexico are built on sustainable behavior, not excessive risk, proven by a stable ~10.5% global decline rate. More importantly, an "Insufficient Funds" decline is not a prevented loss—it is a highly qualified lead. Users are at the point of sale, ready to transact. By failing to provide instant liquidity, NitroBank is missing out on both interchange fees and interest-bearing revenue.
<br>**[Access SQL Queries](Analytics_Engineering/PART_3_Transaction_Success_and_Friction_Removal.sql)**
<br>

<img src="./Visuals/Declined_transactions.png" alt="Declines" width="600"> 

**Strategic Action:** Deploy "Nitro Reserve" via a propensity-driven credit framework:
1. **Mexico (Trust Bridge):** Deploy a $25 USD credit-builder card to users trapped in the 60.8-hour Time-To-Value lag, converting hesitation into funded accounts.
2. **Brazil (Collateralized Liquidity):** Utilize historical vault activity as a behavioral proxy to offer "Limite Garantido," clearing transaction declines with zero systemic default risk.
3. **Colombia (Organic Beta):** Deploy instant, low-value "Nanocredito" lifelines to cover minor checkout shortfalls to prioritize high-loyalty retention.

**Business Impact:** Converting just 20% of "Insufficient Funds" declines (~2,700 transactions) instantly boosts active TPV and transforms NitroBank from a low-margin digital wallet into a highly profitable, full-service bank.

***

## 🔧 Analytics Engineering & Architecture

**Stack:** Databricks SQL (Delta Lake) | ELT | Medallion Architecture | Liquid Clustering | Python | Looker Studio | **[Access SQL Queries](Analytics_Engineering/Bronze_to_Silver_Transition.sql)**

> **Architectural Note:** While this portfolio utilizes static SQL scripts to clearly demonstrate the underlying business logic, the pipeline is engineered following **Delta Live Tables (DLT)** design principles. The focus is on defensive data modeling, strict data quality enforcement, and **compute cost optimization** to build a trustworthy and efficient Medallion architecture:

<img src="./Visuals/Data_Lineage.png" alt="Data Lineage" width="850"> 

### 1. Data Quality Assurance: The Engineering Dashboard

<img src="./Visuals/Data_Quality_Results.png" alt="Failed QA Dashboard" width="850"> 

### 🛠️ Analytics Engineering & Data Quality

#### 1. Data Observability & Quality Guardrails
> **Context:** Raw mobile telemetry is inherently chaotic. To protect downstream analytics from webhook retry storms and client-side clock skew, I developed a suite of diagnostic SQL guardrails acting as proxy DLT Expectations. **[Access SQL Queries](Analytics_Engineering/Data_Quality_Dashboard.sql)**

* **Layer 1 (Structural):** Validates primary key uniqueness and flags technical duplicates in the event logs.
* **Layer 2 (Integrity):** Enforces chronological validity (neutralizing "time-traveling" events) and verifies funnel completeness.
* **Layer 3 (Risk & Anomaly):** Deployed a Bot Velocity Check to identify high-velocity KYC completions (<30s), flagging potential fraudulent actors before they contaminate business metrics.

#### 2. The Silver Layer: FinOps & Processing
* **Deterministic Lineage:** Generated MD5 surrogate keys (user + event + timestamp) to guarantee 100% traceability for raw, ID-less telemetry.
* **FinOps & Compute Optimization:** Strategically utilized Databricks Liquid Clustering on frequently filtered dimensions (`country`, `event_name`, `event_timestamp`). This enables aggressive data skipping, drastically reducing query latency and cloud warehouse costs for downstream Looker Studio dashboards.
* **Precision Deduplication:** Deployed single-pass `QUALIFY ROW_NUMBER() = 1` logic to strip technical duplicates and filter anomalies flagged by the QA dashboard. 

> 💡 **Production Consideration: Data Quarantine Strategy**
> *In this portfolio simulation, the Silver layer aggressively deduplicates records using `QUALIFY ROW_NUMBER() = 1` to optimize compute. In a live enterprise deployment, I would implement a **Quarantine Pattern**. Instead of silently dropping structural fractures, those records would be routed to a `silver_quarantine` table. This ensures 100% Source-to-Warehouse row count reconciliation for financial auditors, while keeping the primary Silver tables pristine for LTV modeling.*

#### 3. Strategic Modelling: Eliminating Survivorship Bias
* **The "Ghost User" Solution:** Engineered a Denormalized Star Schema to capture the 67% of traffic that drops off pre-registration, persisting Country and Marketing Source directly on the `silver_events` fact table.
* **Zero-Join BI Analysis:** Empowered **Looker Studio executive dashboards** to analyze unregistered traffic directly from the fact table. This slashes BI query latency and bypasses the compute costs of expensive distributed joins.

#### 4. The Gold Layer: Financial Integrity & Evolution
* **State Machine Enforcement:** Embedded logic to strictly enforce the irreversible sequential flow (KYC → Activation → Spend). Timeline checks guarantee chronological consistency so no spending occurs before account creation.
* **Audit-Grade Financial Hardening:** Designed the architecture to support dynamic `LEFT JOIN`s on a `dim_exchange_rates` table. Joining on `currency_code` and `DATE(transaction_timestamp)` allows historical purchases to be parsed against daily market rates, providing point-in-time auditability for regulatory compliance.
* **Reconciliation Audit:** Achieved a <0.02% variance during cross-layer validation between the `silver_events` tracking table (124,498 users) and the `silver_transactions` core database (124,471 users), ensuring dashboard metrics map 100% to known entities.
