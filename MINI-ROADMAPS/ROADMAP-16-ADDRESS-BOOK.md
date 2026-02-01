# ROADMAP-16 — Address Book & Contacts

**Theme:** Address Management  
**Priority:** P1 (High)  
**Target Outcome:** Full address book with nicknames, recent recipients, and quick access

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **[High] No Address Book / Contacts** (Section 3.4 / Top 10)
- **[High] No Recent Recipients List** (Section 3.4)
- **Top 10 Failures #5** — No Address Book
- **Phase 1 P1-14** — Address book with nicknames
- **Blueprint 5.3** — Send Flow with contacts
- **Edge Case #30** — User sends to same address repeatedly
- **Edge Case #31** — User has contact on multiple networks
- **Microcopy Pack** — Contact management

---

## 2) User Impact

**Before:**
- Must copy-paste addresses every time
- No way to save trusted addresses
- No nicknames for addresses

**After:**
- Save addresses with nicknames
- Recent recipients for quick access
- Search contacts when sending
- Multi-network support per contact

---

## 3) Scope

**Included:**
- Address book storage
- Add/edit/delete contacts
- Nickname assignment
- Multi-network addresses per contact
- Recent recipients list
- Search contacts
- Integration with Send flow

**Not Included:**
- Contact import from phone
- ENS/Unstoppable domain resolution
- Contact sync across devices

---

## 4) Step-by-Step Tasks

### Design Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| D1: Address book screen | List of contacts | Alphabetical or recent | Settings → Contacts |
| D2: Contact card | Name, addresses, avatar | Edit button | Detail view |
| D3: Add contact flow | Name + address fields | Multi-address support | Modal or screen |
| D4: Recent recipients | Horizontal list | In Send flow | Quick tap |
| D5: Contact search | Search by name/address | Real-time filter | In Send flow |
| D6: Contact in confirmation | Show nickname | "Sending to Alice (0x...)" | Clear identification |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: Contact model | Name, addresses, avatar | Codable | Contact struct |
| E2: Contact storage | Persist contacts | Keychain or secure storage | ContactStore |
| E3: Address book view | List all contacts | Alphabetical sort | AddressBookView |
| E4: Add contact view | Input fields | Save to store | AddContactView |
| E5: Edit contact view | Modify existing | Update in store | EditContactView |
| E6: Delete contact | Remove from store | Confirmation dialog | Swipe to delete |
| E7: Multi-address support | Multiple networks | Per-contact | [Address] array |
| E8: Recent recipients | Store last 10 | Ordered by recency | Separate storage |
| E9: Recent recipients view | Horizontal scroll | In SendView | Quick selection |
| E10: Contact search | Filter by name/address | Case-insensitive | Search integration |
| E11: Send integration | Show contacts | Tap to select | AddressPicker |
| E12: Confirmation display | Show nickname | "Sending to Alice" | Lookup on confirm |
| E13: Auto-save prompt | After send to new | "Save to contacts?" | After successful tx |
| E14: Import existing | Import from history | Unique addresses | One-time migration |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: Add contact | Add new contact | Appears in list | Happy path |
| Q2: Edit contact | Change nickname | Updated correctly | Persistence |
| Q3: Delete contact | Remove contact | Gone from list | Confirmation |
| Q4: Multi-address | Add ETH + BTC | Both saved | One contact |
| Q5: Recent recipients | Send to address | Appears in recent | Order check |
| Q6: Search | Search by name | Results shown | Filter test |
| Q7: Send integration | Send to contact | Address filled | Workflow |
| Q8: Confirmation | Confirm send | Nickname shown | Display check |

---

## 5) Acceptance Criteria

- [ ] Address book accessible from Settings
- [ ] Can add contacts with nickname + address
- [ ] Can add multiple addresses per contact (multi-network)
- [ ] Can edit existing contacts
- [ ] Can delete contacts with confirmation
- [ ] Recent recipients list shows last 10
- [ ] Recent recipients accessible in Send flow
- [ ] Can search contacts by name or address
- [ ] Selecting contact fills address in Send flow
- [ ] Confirmation screen shows nickname
- [ ] Prompt to save after sending to new address

---

## 6) Edge Cases & Failure States

| Scenario | Detection | UX Response |
|:---|:---|:---|
| Duplicate address | Comparison check | "This address is already saved as [Name]" |
| Contact with no addresses | Validation | Require at least one address |
| Very long nickname | Length check | Truncate with ellipsis |
| Delete contact with recent tx | No issue | Just removes from contacts |
| Search no results | Empty result | "No contacts match" |
| Address for wrong network | Validation | "Invalid address for [Network]" |

---

## 7) Analytics / Telemetry

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `contact_added` | `has_nickname`, `network_count` | Success |
| `contact_edited` | `field_changed` | Success |
| `contact_deleted` | - | Success |
| `contact_selected` | `context` (send/recent) | Success |
| `recent_recipient_tapped` | `position` (1-10) | Success |
| `contact_search` | `query_length`, `results_count` | Success |
| `save_contact_prompt_shown` | - | Prompt |
| `save_contact_prompt_accepted` | - | Success |
| `save_contact_prompt_dismissed` | - | Dismissed |

---

## 8) QA Checklist

**Manual Tests:**
- [ ] Open Address Book from Settings
- [ ] Add contact with nickname → appears in list
- [ ] Add contact with ETH + BTC addresses → both saved
- [ ] Edit nickname → updated correctly
- [ ] Delete contact → removed after confirmation
- [ ] Send to address → appears in Recent Recipients
- [ ] Recent shows last 10 in order
- [ ] Search "Alice" → matching contact shown
- [ ] Search "0x1234" → matching address shown
- [ ] Tap contact in Send → address filled
- [ ] Confirm send to contact → shows nickname
- [ ] Send to new address → "Save to contacts?" prompt
- [ ] Accept prompt → contact added

**Automated Tests:**
- [ ] Unit test: Contact model serialization
- [ ] Unit test: Recent recipients ordering
- [ ] Unit test: Contact search filtering
- [ ] Integration test: Contact storage
- [ ] UI test: Add contact flow

---

## 9) Effort & Dependencies

**Effort:** S (2-3 days)

**Dependencies:**
- Secure storage for contacts
- Send flow integration

**Risks:**
- Contact sync complexity (deferred)
- ENS resolution complexity (deferred)

**Rollout Plan:**
1. Contact model + storage (Day 1)
2. Address book UI + CRUD (Day 2)
3. Send integration + recent recipients (Day 3)

---

## 10) Definition of Done

- [ ] Address book accessible
- [ ] Add/edit/delete contacts working
- [ ] Multi-address per contact supported
- [ ] Recent recipients displayed
- [ ] Search working
- [ ] Send flow integration complete
- [ ] Nickname shown in confirmations
- [ ] Save prompt after new address
- [ ] Analytics events firing
- [ ] PR reviewed and merged
