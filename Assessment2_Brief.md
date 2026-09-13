# Assessment 2: Domain-Centred iOS MVP

*Continues directly from Assessment 1 (Ezypick — swipe-based restaurant decider).*

## Project Description

Building directly on the domain problem and Lo-Fi prototype you defined in Assessment 1, you will develop a Minimum Viable Product (MVP) iOS application that solves that problem for a real stakeholder.

This is not a demonstration of programming concepts. It is a business solution — designed for a person, in a context, with real consequences if it fails.

By the end of this project you will have produced:

- A functional iOS MVP that addresses a real domain problem
- A clean, semantically layered architecture that a new developer could understand without asking you questions
- A Human-System Architecture diagram showing how your app fits into the broader human workflow
- A structured reflective report on the decisions you made as a solution engineer

> **Note:** If you think your Assessment 1 concept/description does not suit the vision of this assessment, you can change it.

---

## Project Requirements

### 1. Domain-Centred Architecture

#### 1a. Semantic Domain Model Layer

All core types must be named after domain entities, not technical constructs. The naming of your types, properties, and methods must reflect the vocabulary of the industry you are building for.

```swift
// ✅ Required — domain model for a healthcare scenario
/// Represents a single medication administration event recorded by a ward nurse.
/// Business Rule: A new record cannot be created within 4 hours of the previous
/// administration for the same medication and patient.
struct MedicationAdministrationRecord {
    let patientID: PatientIdentifier
    let medicationCode: MedicationCode
    let administeredDosageMg: Double
    let administeredAt: Date
    let recordedByNurse: NurseIdentifier
}

// ❌ Not accepted — generic naming with no domain meaning
struct Record {
    var id: String
    var val: Double
    var time: Date
    var user: String
}
```

Your domain models must be accompanied by DocC documentation that explains:

- What real-world entity or event does this type represent?
- What business rules govern it?

#### 1b. Object-Oriented and Protocol-Oriented Design

Apply OOP and protocol-oriented concepts in service of the domain, not as an exercise in pattern demonstration.

**Classes and Structs** must model real domain entities with meaningful properties and methods:

- Use value types (`struct`) for domain records and data
- Use reference types (`class`) where shared, mutable state is genuinely needed

**Protocols** must reflect domain behaviours, not just technical interfaces:

```swift
// Domain protocol — represents any entity that participates in
// an auditable event (common requirement in regulated industries)
protocol DomainAuditable {
    var recordedAt: Date { get }
    var recordedByUserID: String { get }
    func auditSummary() -> String
}
```

Ask yourself: does this protocol describe something that actually exists in the domain, or am I just adding a protocol to tick a box?

**Inheritance and Composition** must be justified by domain relationships, not by a desire to demonstrate inheritance.

#### 1c. Use Case Layer (Solution Engineering Requirement)

Every significant business operation must be encapsulated in a Use Case struct. This separates *what the app does* (business logic) from *how it looks* (Views) and *where it stores data* (Repositories).

```
App Architecture:
┌─────────────────────────────────┐
│        SwiftUI Views            │
├─────────────────────────────────┤
│       ViewModels (MVVM)         │
├─────────────────────────────────┤
│    ← USE CASE LAYER →           │  ← Required in this assessment
│      SubmitClaimUseCase         │
│      ReviewMedicationUseCase    │
│      FlagTransactionUseCase     │
├─────────────────────────────────┤
│      Domain Models + Repos      │
└─────────────────────────────────┘
```

**Minimum requirement: 3 Use Case structs** covering your app's core business operations.

Each Use Case must have:

- A name that describes a business operation (e.g., `SubmitLeaveRequestUseCase`, not `DataProcessor`)
- DocC documentation explaining the business operation in plain English (optional)
- A typed error enum encoding domain-specific failure states
- At least one unit test covering the happy path and at least one failure case

### 2. SwiftUI User Interface

The UI must be designed for the domain stakeholder identified in Assessment 1 — not a generic user.

This means:

- **Language:** UI labels and button text use domain vocabulary (e.g., "Submit Claim" not "Add Item"; "Patient Ward" not "Category")
- **Error messages:** Written for the human in the domain context, not for a developer (see Section 3)
- **Flow:** The screen sequence follows the stakeholder's actual workflow, as identified in your A1 Human-System Interaction Diagram

**Minimum: 4 functional SwiftUI screens** aligned to your Assessment 1 Lo-Fi prototype.

### 3. Error Handling — Human-System Failure Design

Error handling must be designed from the human's perspective in the domain, not just as a Swift programming exercise.

For each domain error type, you must be able to answer:

- Who encounters this error in the real-world workflow?
- What should the system communicate to them? (in domain-appropriate language, not technical language)
- What can they do next? (recovery path)

```swift
enum MedicationAdministrationError: LocalizedError {
    case dosageIntervalViolation(minimumWaitHours: Int)
    case patientNotFound(patientID: String)
    case medicationContraindicated(reason: String)

    var errorDescription: String? {
        switch self {
        case .dosageIntervalViolation(let hours):
            // Written for a nurse in a clinical setting, not a developer
            return "This medication cannot be administered yet. Minimum interval: \(hours) hours. Check patient chart before proceeding."
        case .patientNotFound(let id):
            return "Patient ID \(id) not found in the ward system. Verify the patient wristband and try again."
        case .medicationContraindicated(let reason):
            return "Administration blocked: \(reason). Contact the prescribing physician."
        }
    }
}
```

Your error enum naming, cases, and messages must reflect the domain. Generic messages like "Something went wrong" are not acceptable.

### 4. Unit Testing

Write unit tests that verify your Use Case logic against real business rules — not just that Swift runs without crashing.

**Minimum: 8 unit tests across your 3 Use Cases**, covering:

- The happy path (valid input, expected output)
- Boundary conditions (edge cases the business rule defines)
- Each major error case

Test names must describe the scenario in domain terms:

```swift
// ✅ Meaningful test name
func test_submitMedicationRecord_fails_whenIntervalIsLessThanFourHours()

// ❌ Not acceptable
func testError1()
```

### 5. Human-System Architecture Diagram (Mandatory Deliverable)

Produce a one-page architecture diagram that shows:

- The app's layer structure (Views → ViewModels → Use Cases → Domain Models → Data)
- The human-system boundary: what the user does, what the app does, and where the boundary lies
- Data flow for the app's primary Use Case — from the user action to the system response and back
- How your architecture aligns with the stakeholder workflow identified in A1

**Tools:** draw.io, Miro, Figma, Lucidchart, or hand-drawn and photographed clearly. Clarity matters more than the tool.

### 6. Git Version Control

Your Git history must reflect a professional development process, not just a single commit at the end.

**Requirements:**

- **Main branch:** stable, tested code only — never commit broken code to main
- **Feature branches:** one per major feature (e.g., `feature/medication-record-ui`, `feature/submit-use-case`) *(optional)*
- **Commit messages:** follow Conventional Commits format — `feat:`, `fix:`, `docs:`, `test:`
- **README.md:** must include project overview, domain context, architecture summary, and setup instructions *(optional)*

### 7. Reflective Report (Mandatory)

600–800 words covering:

- **Domain understanding:** What did you learn about your chosen domain that changed how you designed or wrote the code? Give a specific example.
- **Architecture decisions:** Why did you choose the Use Cases you chose? What business rules do they protect, and why do those rules matter in the real domain?
- **Human-system design:** Identify one moment in your app's flow where a human could make a mistake. How did you design the system to handle it, and why?
- **What you would do next:** If you had another two weeks, what one architectural or design change would you make? Why?

This report is the primary evidence that you are thinking like a Solution Engineer, not just a coder.

---

## Deliverables

| # | Deliverable | Format | Requirement |
|---|---|---|---|
| 1 | Functional iOS MVP | Xcode project (zip) + Git link | Minimum 4 screens, 3 Use Cases |
| 2 | Human-System Architecture Diagram | PDF or PNG | One page — layers, boundary, primary data flow |
| 3 | DocC Documentation (optional) | Built in Xcode, exported as HTML | Covers all domain models and Use Cases |
| 4 | Unit Tests | Inside the Xcode project | Minimum 8 tests with domain-meaningful names |
| 5 | Git Repository (some reqs. optional) | GitHub or GitLab link | Branching, meaningful commits, README |
| 6 | Reflective Report | PDF | 600–800 words, mandatory |

---

## Assessment Criteria & Rubric

| Criterion | What is being assessed | Weight |
|---|---|---|
| **Domain Solution Quality** | The app solves a meaningful domain problem. UI language, error messages, data model, and Use Case names reflect the domain — not a generic app. | 30% |
| **Semantic Architecture** | Domain models are meaningfully named with DocC. Use Cases encapsulate real business rules. MVVM + Use Case layer is correctly structured. | 25% |
| **Error Handling & Human-System Design** | Errors are designed for the human in the domain context. Recovery paths are clear. The architecture diagram accurately models the human-system boundary. | 20% |
| **Code Correctness & Testing** | App is functional. Unit tests cover core Use Cases including failure states. Test names are meaningful. | 20% |
| **Documentation** | DocC comments explain domain intent, not just implementation. README is complete and professional. | 0% |
| **Version Control** | Branching strategy followed (optional). Commits are structured and meaningful. Reflective report demonstrates solution engineering thinking. | 5% |
