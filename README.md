# NitroBank-LATAM-Fintech-Growth-Audit

## Executive Summary

This three-part strategic analysis evaluates the expansion and operational efficiency of the neobank **NitroBank** across Latin America. By tracking **over 1 million potential users across Brazil, Mexico, and Colombia** between January 2024 and January 2026, this report identifies the technical bottlenecks, financial drivers, and product innovations required to dominate the LATAM fintech landscape.

* **Part 1: Growth & Acquisition:** A diagnostic breakdown of top-of-funnel conversion, identifying a 67% Document Submission "Wall" and the $0 marketing-spend opportunity to unlock explosive user growth by resolving technical KYC crashes to recover 301,500 "stuck" users.
* **Part 2: Unit Economics & Profitability:** An analysis of the "Profitability Paradox," shifting strategy away from low-margin volume toward Mexico’s elite **1.15% Take Rate** and high-LTV referral channels.
* **Part 3: Transaction Success & Friction Removal:** A deep dive into **>145,000 transactions** to validate market stability and transform "Insufficient Funds" declines into a high-margin micro-credit product line.

**Strategic Imperative:** By repairing the KYC ingestion pipeline, pivoting acquisition to Mexico's high-yield segments, and monetizing declined transactions through a new micro-credit product, NitroBank can immediately transition from a low-margin "wallet" into a highly profitable, full-service digital bank.


### Data Architecture & Scope 

This project follows a **Medallion Architecture**. The Entity Relationship Diagram (ERD) below represents the **Silver Layer**, which serves as the cleaned, relational source of truth. Full  **Medallion Transformation** flow and **Directed Acyclic Graph (DAG)** can be accessed [HERE] in Analytics Engineering part. 

<img src="./Visuals/ERD.png" alt="funnel" width="700">

**Silver layer scale and data volume:**

* **silver_events** (fact table): **1.62M+** event records processed, capturing detailed user interactions, device specifications, and marketing attribution. Optimized via liquid clustering by `country`, `event_name`, and `event_timestamp`. Features deterministic MD5 surrogate key generation and strict deduplication by user, event, and timestamp.
* **silver_users** (dimension table): **450K+** unique registered users analyzed. Filtered strictly for registered accounts (excluding ghost users) and deduplicated by user ID. Highly optimized for regional and temporal queries via clustering on `country` and `user_created_at`.
* **silver_transactions** (fact table): **145K+** transaction records processed, monitoring payment amounts, transaction statuses, and decline reasons. Deduplicated by unique transaction ID and clustered by `ts_created_at` and `user_id` for rapid financial and time-series reporting.




## Part 1: Growth and Acquisition 
<small>*[Access the Gold Layer SQL Pipeline used to generate these funnel insights](Analytics_Engineering/Part1_Gold_Layer_Funnel.sql)*</small>

### 1. The Divide: Elite Retention vs. Onboarding Failure 
NitroBank is a "unicorn" product hidden behind a broken door. We have exceptional product-market fit, but a single operational bottleneck is trapping massive, zero-CAC revenue. Optimizing our onboarding to an industry-standard 60% completion rate will trigger explosive bottom-up growth with **$0 in additional marketing spend.**

* **The KYC Wall:** We are losing **67%** of our acquired leads (~301,500) precisely at Document Submission.
* **Elite Retention:** The intent is there. Once users clear that KYC wall, a staggering **90.3%** fund their accounts almost immediately.
* **Top-of-Funnel Inefficiency:** We are currently subsidizing high-bounce traffic on Facebook Ads globally (27.9% signup rate) while under-leveraging top-of-funnel conversion winners like Instagram Ads (53.6%) and Organic Search (50.2%). However, **acquisition cost is only half the equation.** Before aggressively cutting the Facebook budget, we must map these specific acquisition channels to downstream user behaviour to ensure we aren't accidentally cutting off a low-converting but high-spending demographic.
* **The "Hidden Gem":** Colombia drives our lowest traffic volume but yields top-tier intent (50.1% signup rate) and our highest Global Monetization Rate (13.8%), making it prime for scaled top-of-funnel investment.

<img src="./Visuals/users_funnel.png" alt="funnel" width="700">


### 2. Strategic Diagnosis: The DROP-OFF 
* **Ruling Out Culture & Psychology:** The KYC drop-off is practically identical across Brazil (33.1%), Mexico (33.2%), and Colombia (33.0%). High-intent organic users fail at the same rate. This is definitively not a localized trust or motivation issue.
* **The Primary Suspect (Technical Failure):** With an overwhelmingly Android user base (e.g., 523k Android vs. 105k iOS in Brazil), this universal failure points to a severe technical crash—likely an Android Camera SDK or UI loop during document upload.
* **The Telemetry Blind Spot:** A cohort of ~32,000 "Unknown OS" users boasts a 100% Signup Rate and a staggering **26.8% Monetization Rate** (vs. Android's 11.6%). This signals bypassed telemetry (likely Web-to-App handoffs or API partners) and represents a highly profitable untapped channel.

### 3. Action plan 

**Phase 1: The Technical "Fix It" Sprint (Days 1–7)**
* **Crash Telemetry Audit:** Isolate KYC module timeouts and crashes by **Device Model, OS, and Network Type** to solve for LATAM's volatile mobile data environments.
* **Granular Funnel Tracking:** Implement screen-by-screen drop-off logs (ID Front/Back/Selfie) and monitor **"Activation Lag"** to pinpoint the exact friction point in the Android SDK.

**Phase 2: Data-Driven Marketing Reallocation**
* **LTV Validation:** Before diverting the **Facebook Ads budget** (27.9% signup) to Instagram or Organic, map cohort-specific **Take Rates** and **LTV** to ensure we aren't cutting a low-converting but high-spending demographic.
* **Conditional Shift:** Transition spend only once high-value profitability is confirmed in alternative channels.

**Phase 3: The Activation & Recovery Campaign**
* **Incentive Restructuring:** Move the reward trigger from "KYC Completion" to **"First Account Funding"** to protect the ROI baseline and ensure revenue-generating behaviour.
* **Correct the ROI Baseline:** Do not assume the 90.3% organic funding rate will apply to an incentivized cohort. Users motivated by cash bonuses inherently show higher immediate churn and lower long-term funding rates.
* **Deploy Localized Tiers & Messaging:** Replace the generic $5 USD offer with localized, psychologically round numbers (in the Spanish or Portuguese if the account was created in these languages) that feel native and substantial in each market:

  
  <img src="./Visuals/incentive_tiers.png" alt="Incentive tiers" width="350">


* **Gated A/B Testing:** Deploy a recovery campaign to the **301,500 "Stuck" users**. It is critical to maintain a strict hold on this spend until Phase 1 validates that the technical UI crashes are resolved.

### 4. Looking Ahead: Bridging To Part 2 

While fixing the KYC bottleneck resolves the volume equation, user acquisition means nothing without profitability. Part 2 shifts from funnel volume to financial health, analysing Total Payment Volume (TPV), Take Rates, and Average Revenue Per Active Customer (ARPAC) to validate NitroBank's true economic engines in LATAM.

<br>


