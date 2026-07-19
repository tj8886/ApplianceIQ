-- ============================================================================
-- Appliance IQ Academy — V1 Seed Script
-- ============================================================================
CREATE TABLE IF NOT EXISTS academy_volumes (
  id          SERIAL PRIMARY KEY,
  vol_number  INT UNIQUE NOT NULL,
  title       TEXT NOT NULL,
  description TEXT,
  sort_order  INT DEFAULT 0
);

CREATE TABLE IF NOT EXISTS academy_chapters (
  id             SERIAL PRIMARY KEY,
  volume_id      INT REFERENCES academy_volumes(id) ON DELETE CASCADE,
  chapter_number INT UNIQUE NOT NULL,
  title          TEXT NOT NULL,
  slug           TEXT UNIQUE NOT NULL,
  intro          TEXT,
  sort_order     INT DEFAULT 0
);

CREATE TABLE IF NOT EXISTS academy_progress (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  chapter_id INT NOT NULL REFERENCES academy_chapters(id) ON DELETE CASCADE,
  completed_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, chapter_id)
);

INSERT INTO academy_volumes (vol_number, title, description, sort_order) VALUES
 (1,  'Foundations of Appliance Retail',            'The modern buyer, salesperson mindset, ethics, personal operating system, AI-assisted workflow, and the 90-day ramp.', 1),
 (2,  'Product Knowledge: Core Categories',         'Refrigeration, laundry, cooking, dishwashers, ventilation — FAB selling, the brand ladder, top customer questions.', 2),
 (3,  'Product Knowledge: Advanced & Luxury',       'Built-in and integrated, luxury brands, outdoor kitchens, specialty units, smart home, energy ratings and rebates.', 3),
 (4,  'The Retail Floor Sales Process',             'The greeting, needs discovery, lifestyle demo, kitchen package selling, browser-to-buyer conversion, the write-up.', 4),
 (5,  'B2C Closing & Objection Handling',           'ACRA for retail — cheaper online, spouse delay, think about it, floor closing techniques, same-visit vs follow-up close.', 5),
 (6,  'Attach Rate & Ticket Economics',             'Warranties, installation, haul-away, accessories, financing, promotions, the kitchen-package multiplier, margin awareness.', 6),
 (7,  'B2C Follow-Up & Repeat Business',            'Quote follow-up systems, abandoned-sale recovery, post-delivery check-ins, replacement cycles, reviews, referrals.', 7),
 (8,  'B2B Foundations: The Trade Channel',         'Custom builders, renovation contractors, kitchen & bath designers, property managers — how each buys and decides.', 8),
 (9,  'Trade Business Development',                 'Territory mapping, builder outreach, designer showroom events, association networking, the spec-in strategy.', 9),
 (10, 'Trade Account Management & Contract Selling','Builder programs, designer arrangements, unit-turn packages, multi-unit quoting, job-site coordination, net terms.', 10),
 (11, 'Trade Growth & Account Penetration',         'One project to all projects, the designer referral engine, property portfolio expansion, becoming the market go-to.', 11),
 (12, 'Psychology of Appliance Sales',              'Why retail and trade buyers buy, trust dynamics, presence, buyer archetypes, influence, closing psychology, top 1% mindset.', 12),
 (13, 'AI for Appliance Sales',                     'AI-assisted quoting, comparisons, follow-up automation, trade research, spec summaries, the AI Command Console.', 13),
 (14, 'Metrics, Coaching & Performance',            'Average ticket, attach rate, warranty penetration, close rate, GM%, scorecards, KPI diagnostics, 30/60/90 reviews.', 14),
 (15, 'Operations That Protect the Sale',           'Delivery and install coordination, damage handling, backorders, promo administration, the sales-to-ops handoff.', 15),
 (16, 'Leadership & Store Growth',                  'Hiring salespeople, running the floor, huddles, managing to the scorecard, building the trade desk, multi-location standards.', 16)
ON CONFLICT (vol_number) DO UPDATE
SET title=EXCLUDED.title, description=EXCLUDED.description, sort_order=EXCLUDED.sort_order;

INSERT INTO academy_chapters (volume_id, chapter_number, title, slug, intro, sort_order) VALUES
 ((SELECT id FROM academy_volumes WHERE vol_number=1), 1, 'Chapter 1 — Welcome to Appliance IQ',                'chapter-1-welcome-to-appliance-iq',       'What this system is, why it exists, and how to use it to build a career in appliance sales.', 1),
 ((SELECT id FROM academy_volumes WHERE vol_number=1), 2, 'Chapter 2 — The Modern Appliance Buyer',             'chapter-2-the-modern-appliance-buyer',    'Who walks into an appliance store in 2026, what they already know, and what they need from you.', 2),
 ((SELECT id FROM academy_volumes WHERE vol_number=1), 3, 'Chapter 3 — The Appliance IQ Salesperson Mindset',   'chapter-3-the-salesperson-mindset',       'The beliefs and standards that separate career professionals from clerks.', 3),
 ((SELECT id FROM academy_volumes WHERE vol_number=1), 4, 'Chapter 4 — Ethics, Honesty and the Long Game',      'chapter-4-ethics-and-trust',              'Why integrity is a commercial strategy in a repeat-purchase, review-driven business.', 4),
 ((SELECT id FROM academy_volumes WHERE vol_number=1), 5, 'Chapter 5 — Your Personal Operating System',         'chapter-5-store-operating-system',        'The daily and weekly structure that turns a sales job into a sales business.', 5),
 ((SELECT id FROM academy_volumes WHERE vol_number=1), 6, 'Chapter 6 — Personal Brand and Communication',       'chapter-6-brand-and-communication',       'How you present, speak, write, and follow up — the layer that carries every sale.', 6),
 ((SELECT id FROM academy_volumes WHERE vol_number=1), 7, 'Chapter 7 — The AI-Assisted Appliance Salesperson',  'chapter-7-the-ai-assisted-salesperson',   'How AI fits into appliance retail — what it does well and what it must never do.', 7),
 ((SELECT id FROM academy_volumes WHERE vol_number=1), 8, 'Chapter 8 — Your First 90 Days',                     'chapter-8-your-first-90-days',            'The structured ramp from day one to certified floor professional.', 8)
ON CONFLICT (chapter_number) DO UPDATE
SET title=EXCLUDED.title, slug=EXCLUDED.slug, intro=EXCLUDED.intro, sort_order=EXCLUDED.sort_order;

INSERT INTO academy_chapters (volume_id, chapter_number, title, slug, intro, sort_order) VALUES
 ((SELECT id FROM academy_volumes WHERE vol_number=2),  9, 'Chapter 9 — How to Learn Product: The FAB Framework',            'chapter-9-how-to-learn-product',            'The system for turning spec sheets into selling knowledge — feature, advantage, benefit.', 9),
 ((SELECT id FROM academy_volumes WHERE vol_number=2), 10, 'Chapter 10 — Refrigeration',                                     'chapter-10-refrigeration',                  'The highest-traffic category — configurations, capacity logic, feature tiers, and the five questions.', 10),
 ((SELECT id FROM academy_volumes WHERE vol_number=2), 11, 'Chapter 11 — Laundry',                                           'chapter-11-laundry',                        'Front load versus top load, capacity truths, pedestals and stacking, and dryer technology.', 11),
 ((SELECT id FROM academy_volumes WHERE vol_number=2), 12, 'Chapter 12 — Cooking: Ranges & Cooktops',                        'chapter-12-cooking-ranges-cooktops',        'Gas, electric, and induction — the fuel conversation and the induction demo that converts.', 12),
 ((SELECT id FROM academy_volumes WHERE vol_number=2), 13, 'Chapter 13 — Cooking: Wall Ovens, Microwaves & Compact Cooking', 'chapter-13-cooking-wall-ovens-microwaves',  'The built-in cooking wall — wall ovens, speed ovens, microwave placement, and renovation selling.', 13),
 ((SELECT id FROM academy_volumes WHERE vol_number=2), 14, 'Chapter 14 — Dishwashers',                                       'chapter-14-dishwashers',                    'Decibels, rack systems, wash performance, and the installation realities that make the sale.', 14),
 ((SELECT id FROM academy_volumes WHERE vol_number=2), 15, 'Chapter 15 — Ventilation',                                       'chapter-15-ventilation',                    'The most under-sold category — CFM pairing, duct reality, hood types, and the system sale.', 15),
 ((SELECT id FROM academy_volumes WHERE vol_number=2), 16, 'Chapter 16 — The Brand Ladder & Tiering',                        'chapter-16-the-brand-ladder',               'Tiers, brand identities, family trees, and how to answer the brand question honestly.', 16)
ON CONFLICT (chapter_number) DO UPDATE
SET title=EXCLUDED.title, slug=EXCLUDED.slug, intro=EXCLUDED.intro, sort_order=EXCLUDED.sort_order;

INSERT INTO academy_chapters (volume_id, chapter_number, title, slug, intro, sort_order) VALUES
 ((SELECT id FROM academy_volumes WHERE vol_number=4), 25, 'Chapter 25 — The Greeting: Opening Without Triggering',      'chapter-25-the-greeting',                  'The first thirty seconds decide whether you get a conversation or a defensive shield.', 25),
 ((SELECT id FROM academy_volumes WHERE vol_number=4), 26, 'Chapter 26 — Needs Discovery: The Diagnostic Conversation',  'chapter-26-needs-discovery',               'What to ask, in what order, and how to listen for the real purchase driver.', 26),
 ((SELECT id FROM academy_volumes WHERE vol_number=4), 27, 'Chapter 27 — The Lifestyle Demo',                            'chapter-27-the-lifestyle-demo',            'Demonstrating against the customer''s life instead of the spec card.', 27),
 ((SELECT id FROM academy_volumes WHERE vol_number=4), 28, 'Chapter 28 — Building the Complete Ticket',                  'chapter-28-building-the-complete-ticket',  'Delivery, installation, haul-away, accessories, protection — quoting like a professional.', 28),
 ((SELECT id FROM academy_volumes WHERE vol_number=4), 29, 'Chapter 29 — The Kitchen Package Sale',                      'chapter-29-the-kitchen-package-sale',      'The highest-ticket sale on the retail floor — recognition, architecture, coordination.', 29),
 ((SELECT id FROM academy_volumes WHERE vol_number=4), 30, 'Chapter 30 — Working Multiple Customers & Floor Craft',      'chapter-30-working-the-floor',             'The Saturday skill — managing several live customers with grace and team discipline.', 30),
 ((SELECT id FROM academy_volumes WHERE vol_number=4), 31, 'Chapter 31 — The Write-Up & Transition to Close',            'chapter-31-the-write-up',                  'Reading readiness, write-up mechanics, and the post-signature minutes that build the relationship.', 31),
 ((SELECT id FROM academy_volumes WHERE vol_number=4), 32, 'Chapter 32 — Browser to Buyer: Capture and Conversion',      'chapter-32-browser-to-buyer',              'The system for customers who don''t buy today — capture standards and the return visit.', 32)
ON CONFLICT (chapter_number) DO UPDATE
SET title=EXCLUDED.title, slug=EXCLUDED.slug, intro=EXCLUDED.intro, sort_order=EXCLUDED.sort_order;

INSERT INTO academy_chapters (volume_id, chapter_number, title, slug, intro, sort_order) VALUES
 ((SELECT id FROM academy_volumes WHERE vol_number=5), 33, 'Chapter 33 — The Psychology of the Ask',                       'chapter-33-the-psychology-of-the-ask',   'Why salespeople don''t ask for the business, why customers need them to, and closing as a service.', 33),
 ((SELECT id FROM academy_volumes WHERE vol_number=5), 34, 'Chapter 34 — ACRA: The Objection Handling Framework',          'chapter-34-acra-objection-framework',    'Acknowledge, Clarify, Reframe, Advance — the firm-standard structure for every objection.', 34),
 ((SELECT id FROM academy_volumes WHERE vol_number=5), 35, 'Chapter 35 — ''I Can Get It Cheaper Online'': The Full Defence','chapter-35-cheaper-online',              'The defining objection of modern appliance retail — the complete-ticket line-up and price-match discipline.', 35),
 ((SELECT id FROM academy_volumes WHERE vol_number=5), 36, 'Chapter 36 — The Spouse Delay & The Absent Decision-Maker',    'chapter-36-the-spouse-delay',            'The objection that is usually true — prevention, the kitchen-table kit, and closing the household.', 36),
 ((SELECT id FROM academy_volumes WHERE vol_number=5), 37, 'Chapter 37 — ''I Need to Think About It''',                    'chapter-37-i-need-to-think-about-it',    'The vaguest objection on the floor — the sorting question and the structured think.', 37),
 ((SELECT id FROM academy_volumes WHERE vol_number=5), 38, 'Chapter 38 — Price, Discount & Competitor Quote Objections',   'chapter-38-price-discount-competitor',   'Discount discipline, the competitor quote on the counter, and negotiating without eroding trust.', 38),
 ((SELECT id FROM academy_volumes WHERE vol_number=5), 39, 'Chapter 39 — The Seven Closing Techniques for the Retail Floor','chapter-39-seven-closing-techniques',   'The complete closing toolkit — seven techniques and the floor moments each one fits.', 39),
 ((SELECT id FROM academy_volumes WHERE vol_number=5), 40, 'Chapter 40 — Follow-Up Closing & The Second-Visit Close',      'chapter-40-the-follow-up-close',         'Closing the sale that left the floor — the phone close, the return visit, and the re-quote moment.', 40)
ON CONFLICT (chapter_number) DO UPDATE
SET title=EXCLUDED.title, slug=EXCLUDED.slug, intro=EXCLUDED.intro, sort_order=EXCLUDED.sort_order;

INSERT INTO academy_chapters (volume_id, chapter_number, title, slug, intro, sort_order) VALUES
 ((SELECT id FROM academy_volumes WHERE vol_number=8), 41, 'Chapter 41 — The Trade Channel: Why It Exists and What It''s Worth', 'chapter-41-the-trade-channel',          'The second engine — what trade business is and the career mathematics of an account book.', 41),
 ((SELECT id FROM academy_volumes WHERE vol_number=8), 42, 'Chapter 42 — The Custom Builder',                                    'chapter-42-the-custom-builder',         'The trade book''s anchor account — how custom builders work and the service model that wins a decade.', 42),
 ((SELECT id FROM academy_volumes WHERE vol_number=8), 43, 'Chapter 43 — The Renovation Contractor',                             'chapter-43-the-renovation-contractor',  'The highest-frequency account in residential trade — the chaos they live in and the behaviours that make you infrastructure.', 43),
 ((SELECT id FROM academy_volumes WHERE vol_number=8), 44, 'Chapter 44 — The Kitchen & Bath Designer',                           'chapter-44-the-kitchen-bath-designer',  'The channel''s highest-leverage relationship — specification power and the partnership machinery.', 44),
 ((SELECT id FROM academy_volumes WHERE vol_number=8), 45, 'Chapter 45 — The Interior Designer & Architect',                     'chapter-45-interior-designer-architect','The prestige specifiers — luxury-tier projects and the support model that makes you their appliance department.', 45),
 ((SELECT id FROM academy_volumes WHERE vol_number=8), 46, 'Chapter 46 — The Property Manager',                                  'chapter-46-the-property-manager',       'The volume buyer — unit turns, the standard-unit program, and frictionless portfolio service.', 46),
 ((SELECT id FROM academy_volumes WHERE vol_number=8), 47, 'Chapter 47 — Trade Psychology: How Trade Buyers Decide',             'chapter-47-trade-psychology',           'The decision psychology shared across the cast, where each buyer diverges, and trust mechanics.', 47),
 ((SELECT id FROM academy_volumes WHERE vol_number=8), 48, 'Chapter 48 — The Trade Desk: Setting Up Your B2B Operation',         'chapter-48-the-trade-desk',             'The operational architecture — running trade inside a retail floor with systems and boundaries.', 48)
ON CONFLICT (chapter_number) DO UPDATE
SET title=EXCLUDED.title, slug=EXCLUDED.slug, intro=EXCLUDED.intro, sort_order=EXCLUDED.sort_order;

INSERT INTO academy_chapters (volume_id, chapter_number, title, slug, intro, sort_order) VALUES
 ((SELECT id FROM academy_volumes WHERE vol_number=9), 49, 'Chapter 49 — Territory Mapping & The Target List',                    'chapter-49-territory-mapping',            'Sizing your market, finding every buyer in it, and building the ranked target list.', 49),
 ((SELECT id FROM academy_volumes WHERE vol_number=9), 50, 'Chapter 50 — The Warm Path: Mining Your Existing Book',               'chapter-50-the-warm-path',                'The fastest accounts come from relationships you already have — the bridge call and referral engine.', 50),
 ((SELECT id FROM academy_volumes WHERE vol_number=9), 51, 'Chapter 51 — Trade Outreach: The Builder Cold Call & First Contact',  'chapter-51-trade-outreach-first-contact', 'The research-first standard and the opening that earns thirty seconds, per buyer type.', 51),
 ((SELECT id FROM academy_volumes WHERE vol_number=9), 52, 'Chapter 52 — Outreach Sequences: Email, Text & The Persistence System','chapter-52-outreach-sequences',          'Multi-touch architecture, the value-first touch library, and persistence discipline.', 52),
 ((SELECT id FROM academy_volumes WHERE vol_number=9), 53, 'Chapter 53 — The First Meeting: Trade Discovery & The Account Pitch', 'chapter-53-the-first-meeting',            'Trade discovery, the capability story, the terms conversation, and the first-project close.', 53),
 ((SELECT id FROM academy_volumes WHERE vol_number=9), 54, 'Chapter 54 — Association Networking & The Rooms Where Trade Gathers', 'chapter-54-association-networking',       'Which associations matter, the member-not-vendor posture, and converting rooms into pipeline.', 54),
 ((SELECT id FROM academy_volumes WHERE vol_number=9), 55, 'Chapter 55 — Showroom Events & The Designer Evening',                 'chapter-55-showroom-events',              'Turning your floor into a BD engine — event formats, execution standards, and follow-up conversion.', 55),
 ((SELECT id FROM academy_volumes WHERE vol_number=9), 56, 'Chapter 56 — Displacing the Incumbent: The Spec-In Strategy',         'chapter-56-displacing-the-incumbent',     'The displacement doctrine, the five wedges, the spec-in play, and the patient tier-one campaign.', 56)
ON CONFLICT (chapter_number) DO UPDATE
SET title=EXCLUDED.title, slug=EXCLUDED.slug, intro=EXCLUDED.intro, sort_order=EXCLUDED.sort_order;

INSERT INTO academy_chapters (volume_id, chapter_number, title, slug, intro, sort_order) VALUES
 ((SELECT id FROM academy_volumes WHERE vol_number=10), 57, 'Chapter 57 — From First Project to Account: The Consolidation Playbook', 'chapter-57-consolidation-playbook',       'The consolidation sequence that converts one proven project into the account''s standing flow.', 57),
 ((SELECT id FROM academy_volumes WHERE vol_number=10), 58, 'Chapter 58 — The Account Review: Diagnostics, Share & Leakage',          'chapter-58-the-account-review',           'The quarterly ritual — the share question, leakage diagnostics, and the review meeting.', 58),
 ((SELECT id FROM academy_volumes WHERE vol_number=10), 59, 'Chapter 59 — Builder Programs & Volume Agreements',                      'chapter-59-builder-programs',             'Formalising the anchor relationships — program structures, tiers, and the agreement conversation.', 59),
 ((SELECT id FROM academy_volumes WHERE vol_number=10), 60, 'Chapter 60 — Multi-Unit Project Quoting',                                'chapter-60-multi-unit-quoting',           'The quote as competitive weapon — package architecture, speed standards, and margin protection.', 60),
 ((SELECT id FROM academy_volumes WHERE vol_number=10), 61, 'Chapter 61 — Job-Site Coordination & Delivery for Construction',         'chapter-61-job-site-coordination',        'Construction-calendar fluency, site-delivery craft, and the coordination that makes you infrastructure.', 61),
 ((SELECT id FROM academy_volumes WHERE vol_number=10), 62, 'Chapter 62 — Contract Pricing Discipline, Net Terms & Credit',           'chapter-62-contract-pricing-terms-credit','Holding contract pricing under pressure, net terms, credit risk, and the receivables conversation.', 62),
 ((SELECT id FROM academy_volumes WHERE vol_number=10), 63, 'Chapter 63 — Multi-Threading & Institutionalising the Relationship',    'chapter-63-multi-threading',              'Accounts that survive departures — threading both sides and building institutional preference.', 63),
 ((SELECT id FROM academy_volumes WHERE vol_number=10), 64, 'Chapter 64 — Account Rescue: Failures, Complaints & The Save',           'chapter-64-account-rescue',               'The failure taxonomy, the rescue protocol, the complaint as gift, and the save.', 64)
ON CONFLICT (chapter_number) DO UPDATE
SET title=EXCLUDED.title, slug=EXCLUDED.slug, intro=EXCLUDED.intro, sort_order=EXCLUDED.sort_order;

INSERT INTO academy_chapters (volume_id, chapter_number, title, slug, intro, sort_order) VALUES
 ((SELECT id FROM academy_volumes WHERE vol_number=11), 65, 'Chapter 65 — Penetration: One Project to All Projects',                  'chapter-65-account-penetration',          'The penetration ladder and the share-growth playbook per buyer type.', 65),
 ((SELECT id FROM academy_volumes WHERE vol_number=11), 66, 'Chapter 66 — The Designer Referral Engine & Network Growth',             'chapter-66-designer-referral-engine',     'The book referring itself — referral engines per buyer type and the connector position.', 66),
 ((SELECT id FROM academy_volumes WHERE vol_number=11), 67, 'Chapter 67 — Portfolio Expansion: Growing Property Accounts',            'chapter-67-portfolio-expansion',          'Building-by-building penetration, the refresh upsell, and the management-firm ladder.', 67),
 ((SELECT id FROM academy_volumes WHERE vol_number=11), 68, 'Chapter 68 — The Go-To Position: Becoming the Market''s Default',        'chapter-68-the-go-to-position',           'Market position as an asset — reputation architecture and visibility systems.', 68),
 ((SELECT id FROM academy_volumes WHERE vol_number=11), 69, 'Chapter 69 — Account-Based Growth Planning',                             'chapter-69-account-growth-planning',      'The one-page account plan, the book strategy, and the planning rhythm.', 69),
 ((SELECT id FROM academy_volumes WHERE vol_number=11), 70, 'Chapter 70 — Market Intelligence for Trade Clients',                     'chapter-70-market-intelligence',          'Intelligence as a service — the watching disciplines and the advisor position.', 70),
 ((SELECT id FROM academy_volumes WHERE vol_number=11), 71, 'Chapter 71 — Defending the Book: Competitive Defence & Churn Prevention','chapter-71-defending-the-book',           'Thinking like your attacker, the churn signal system, and counter-displacement.', 71),
 ((SELECT id FROM academy_volumes WHERE vol_number=11), 72, 'Chapter 72 — Scaling the Book: Capacity & The Specialist''s Ceiling',    'chapter-72-scaling-the-book',             'The honest ceiling, the leverage systems, the trade team, and the career the book built.', 72)
ON CONFLICT (chapter_number) DO UPDATE
SET title=EXCLUDED.title, slug=EXCLUDED.slug, intro=EXCLUDED.intro, sort_order=EXCLUDED.sort_order;

INSERT INTO academy_chapters (volume_id, chapter_number, title, slug, intro, sort_order) VALUES
 ((SELECT id FROM academy_volumes WHERE vol_number=3), 17, 'Chapter 17 — The Luxury Customer & How Luxury Selling Differs', 'chapter-17-the-luxury-customer',      'Who buys luxury appliances, what they are actually buying, and the posture the tier demands.', 17),
 ((SELECT id FROM academy_volumes WHERE vol_number=3), 18, 'Chapter 18 — Built-In & Integrated Refrigeration',              'chapter-18-builtin-refrigeration',    'Built-in versus integrated versus columns, the engineering deltas, and panel-ready craft.', 18),
 ((SELECT id FROM academy_volumes WHERE vol_number=3), 19, 'Chapter 19 — Pro Ranges & Luxury Cooking',                      'chapter-19-pro-ranges-luxury-cooking','The 36-to-60-inch universe, dual fuel and luxury induction, and selling performance honestly.', 19),
 ((SELECT id FROM academy_volumes WHERE vol_number=3), 20, 'Chapter 20 — Specialty Categories: Wine, Coffee, Outdoor',      'chapter-20-specialty-categories',     'Wine preservation, built-in coffee, outdoor kitchens, and the delight layer.', 20),
 ((SELECT id FROM academy_volumes WHERE vol_number=3), 21, 'Chapter 21 — Panel-Ready & The Integration Craft',              'chapter-21-integration-craft',        'The integrated kitchen as a system — millwork coordination and fit disciplines.', 21),
 ((SELECT id FROM academy_volumes WHERE vol_number=3), 22, 'Chapter 22 — The Luxury Brand Landscape & Lead-Time Mastery',   'chapter-22-luxury-brand-landscape',   'The top-tier map, ordering realities, and the lead-time fluency that runs luxury projects.', 22),
 ((SELECT id FROM academy_volumes WHERE vol_number=3), 23, 'Chapter 23 — The Luxury Sale Process & White-Glove Delivery',   'chapter-23-luxury-sale-process',      'The consultation model, proposal craft, order-to-install, and the white-glove standard.', 23),
 ((SELECT id FROM academy_volumes WHERE vol_number=3), 24, 'Chapter 24 — Smart Home & Connected Appliances',                'chapter-24-smart-connected',          'What smart features actually do, honest use-case selling, privacy, and integration.', 24)
ON CONFLICT (chapter_number) DO UPDATE
SET title=EXCLUDED.title, slug=EXCLUDED.slug, intro=EXCLUDED.intro, sort_order=EXCLUDED.sort_order;

INSERT INTO academy_chapters (volume_id, chapter_number, title, slug, intro, sort_order) VALUES
 ((SELECT id FROM academy_volumes WHERE vol_number=12), 73, 'Chapter 73 — Buying Psychology: How Decisions Actually Happen', 'chapter-73-buying-psychology',      'Emotion and justification, the two-system decision, loss aversion, and cognitive load.', 73),
 ((SELECT id FROM academy_volumes WHERE vol_number=12), 74, 'Chapter 74 — Trust: The Mechanics of Credibility',              'chapter-74-trust-mechanics',        'Warmth and competence, credibility signals, the trust bank, and repair and transfer.', 74),
 ((SELECT id FROM academy_volumes WHERE vol_number=12), 75, 'Chapter 75 — The Principles of Ethical Influence',              'chapter-75-ethical-influence',      'Reciprocity, commitment, social proof, authority, liking, scarcity — aligned versions only.', 75),
 ((SELECT id FROM academy_volumes WHERE vol_number=12), 76, 'Chapter 76 — Reading People: Signals, Styles & Tension',        'chapter-76-reading-people',         'Decision styles, the nonverbal channel, listening below the words, and adaptive range.', 76),
 ((SELECT id FROM academy_volumes WHERE vol_number=12), 77, 'Chapter 77 — Emotional Intelligence & Self-Regulation',         'chapter-77-emotional-intelligence', 'Self-awareness, regulation under pressure, empathy that serves, and emotional labour.', 77),
 ((SELECT id FROM academy_volumes WHERE vol_number=12), 78, 'Chapter 78 — The Psychology of Pricing & Value',                'chapter-78-price-psychology',       'Anchors, framing, value construction, and the fairness instinct.', 78),
 ((SELECT id FROM academy_volumes WHERE vol_number=12), 79, 'Chapter 79 — Habits, Motivation & The Inner Game',              'chapter-79-the-inner-game',         'Habit architecture, motivation mechanics, confidence construction, and the resilience loop.', 79),
 ((SELECT id FROM academy_volumes WHERE vol_number=12), 80, 'Chapter 80 — Difficult Customers & Conflict Psychology',        'chapter-80-conflict-psychology',    'De-escalation mechanics, the difficult taxonomy, boundary craft, and after the storm.', 80)
ON CONFLICT (chapter_number) DO UPDATE
SET title=EXCLUDED.title, slug=EXCLUDED.slug, intro=EXCLUDED.intro, sort_order=EXCLUDED.sort_order;

INSERT INTO academy_chapters (volume_id, chapter_number, title, slug, intro, sort_order) VALUES
 ((SELECT id FROM academy_volumes WHERE vol_number=6), 81, 'Chapter 81 — The Economics of the Attach: Why the Ticket Is the Business', 'chapter-81-attach-economics', 'The margin architecture of appliance retail and the attach arithmetic.', 81),
 ((SELECT id FROM academy_volumes WHERE vol_number=6), 82, 'Chapter 82 — Protection Plans: The Product, The Economics, The Honest Conversation', 'chapter-82-protection-plans', 'How plans work, real repair economics, and the integrity standards.', 82),
 ((SELECT id FROM academy_volumes WHERE vol_number=6), 83, 'Chapter 83 — Delivery, Install, Haul-Away & Accessories', 'chapter-83-logistics-lines', 'The service lines as products, the operational handshake, and accessory discipline.', 83),
 ((SELECT id FROM academy_volumes WHERE vol_number=6), 84, 'Chapter 84 — Financing & The Money Conversation', 'chapter-84-financing-money', 'Promotional financing mechanics, the monthly bridge, and the budget conversation with dignity.', 84)
ON CONFLICT (chapter_number) DO UPDATE
SET title=EXCLUDED.title, slug=EXCLUDED.slug, intro=EXCLUDED.intro, sort_order=EXCLUDED.sort_order;

INSERT INTO academy_chapters (volume_id, chapter_number, title, slug, intro, sort_order) VALUES
 ((SELECT id FROM academy_volumes WHERE vol_number=7), 85, 'Chapter 85 — The Follow-Up System: Architecture of the Second Yes', 'chapter-85-followup-system', 'The pipeline pools operationalised and the sequence library.', 85),
 ((SELECT id FROM academy_volumes WHERE vol_number=7), 86, 'Chapter 86 — The Delivered Base: Repeat Business & The Replacement Cycle', 'chapter-86-repeat-business', 'Replacement-cycle timing, base mining, and lifetime-value arithmetic.', 86),
 ((SELECT id FROM academy_volumes WHERE vol_number=7), 87, 'Chapter 87 — The Referral & Review Engine', 'chapter-87-referral-engine', 'The referral ask, the review system, and advocate cultivation.', 87),
 ((SELECT id FROM academy_volumes WHERE vol_number=7), 88, 'Chapter 88 — Campaigns, Events & The Retail Calendar', 'chapter-88-campaigns-calendar', 'The promo calendar mastered, the event playbook, and quiet-season craft.', 88),
 ((SELECT id FROM academy_volumes WHERE vol_number=7), 89, 'Chapter 89 — Service, Retention & The Long Relationship', 'chapter-89-retention-service', 'The service partnership, retention saves, and the decade view.', 89)
ON CONFLICT (chapter_number) DO UPDATE
SET title=EXCLUDED.title, slug=EXCLUDED.slug, intro=EXCLUDED.intro, sort_order=EXCLUDED.sort_order;

INSERT INTO academy_chapters (volume_id, chapter_number, title, slug, intro, sort_order) VALUES
 ((SELECT id FROM academy_volumes WHERE vol_number=14), 90, 'Chapter 90 — Running Yourself by Numbers: The Measurement Mindset', 'chapter-90-why-measure', 'The measurement mindset, leading versus lagging indicators, and honest data.', 90),
 ((SELECT id FROM academy_volumes WHERE vol_number=14), 91, 'Chapter 91 — The Floor Metrics: Conversion, Ticket & Attach', 'chapter-91-floor-metrics', 'Close rate honestly computed, average ticket anatomy, and the attach dashboard.', 91),
 ((SELECT id FROM academy_volumes WHERE vol_number=14), 92, 'Chapter 92 — Pipeline, Relationship & Money Metrics', 'chapter-92-pipeline-money-metrics', 'Pipeline health, base and referral metrics, the income ledger, and forecasting.', 92),
 ((SELECT id FROM academy_volumes WHERE vol_number=14), 93, 'Chapter 93 — The Review Rituals: Daily, Weekly, Quarterly', 'chapter-93-review-rituals', 'The daily close, the weekly review, the quarterly deep-dive.', 93),
 ((SELECT id FROM academy_volumes WHERE vol_number=14), 94, 'Chapter 94 — Goals, Standards & The Self-Managed Career', 'chapter-94-goals-selfmanagement', 'The goal architecture, standards as identity, and the manager partnership.', 94)
ON CONFLICT (chapter_number) DO UPDATE
SET title=EXCLUDED.title, slug=EXCLUDED.slug, intro=EXCLUDED.intro, sort_order=EXCLUDED.sort_order;

INSERT INTO academy_chapters (volume_id, chapter_number, title, slug, intro, sort_order) VALUES
 ((SELECT id FROM academy_volumes WHERE vol_number=13), 95, 'Chapter 95 — The AI-Powered Salesperson: Foundations & Ground Rules', 'chapter-95-ai-foundations', 'What AI genuinely does for a salesperson and the ground rules.', 95),
 ((SELECT id FROM academy_volumes WHERE vol_number=13), 96, 'Chapter 96 — The Prompting Craft', 'chapter-96-prompting-craft', 'Prompt anatomy, the context brief, iteration technique, and the prompt library.', 96),
 ((SELECT id FROM academy_volumes WHERE vol_number=13), 97, 'Chapter 97 — The Document & Quote Engine', 'chapter-97-document-engine', 'Quotes at speed, communications, trade documents, and verification checklists.', 97),
 ((SELECT id FROM academy_volumes WHERE vol_number=13), 98, 'Chapter 98 — Research & Intelligence Workflows', 'chapter-98-research-intelligence', 'Product research, account intelligence, the market watch, and grounding.', 98),
 ((SELECT id FROM academy_volumes WHERE vol_number=13), 99, 'Chapter 99 — CRM Leverage & The Analyst Sessions', 'chapter-99-crm-analysis', 'Friction-free capture, file synthesis, and pattern-mining sessions.', 99),
 ((SELECT id FROM academy_volumes WHERE vol_number=13), 100, 'Chapter 100 — The AI Roleplay Training System', 'chapter-100-ai-roleplay-training', 'Scenario design, drill rotations, feedback loops, deliberate practice.', 100),
 ((SELECT id FROM academy_volumes WHERE vol_number=13), 101, 'Chapter 101 — AI Operations for the Trade Desk', 'chapter-101-trade-ai-operations', 'The specialist''s machine — daily rhythm, account workflows, BD engine.', 101),
 ((SELECT id FROM academy_volumes WHERE vol_number=13), 102, 'Chapter 102 — The Frontier: Automation, Agents & Staying Current', 'chapter-102-frontier-posture', 'Automation judgment, the agent horizon, and staying current.', 102)
ON CONFLICT (chapter_number) DO UPDATE
SET title=EXCLUDED.title, slug=EXCLUDED.slug, intro=EXCLUDED.intro, sort_order=EXCLUDED.sort_order;

INSERT INTO academy_chapters (volume_id, chapter_number, title, slug, intro, sort_order) VALUES
 ((SELECT id FROM academy_volumes WHERE vol_number=15), 103, 'Chapter 103 — Why Salespeople Need Operations Literacy', 'chapter-103-operations-literacy', 'The store as a system and why the best sellers understand the machine.', 103),
 ((SELECT id FROM academy_volumes WHERE vol_number=15), 104, 'Chapter 104 — Inventory: What''s Really in the Building', 'chapter-104-inventory-fundamentals', 'Statuses decoded, counts and shrink, and selling with inventory truth.', 104),
 ((SELECT id FROM academy_volumes WHERE vol_number=15), 105, 'Chapter 105 — Purchasing, Programs & Merchandise Planning', 'chapter-105-purchasing-merchandise-planning', 'How the floor gets stocked and the feedback loop into purchasing.', 105),
 ((SELECT id FROM academy_volumes WHERE vol_number=15), 106, 'Chapter 106 — Delivery Operations: Routes, Crews & The Last Mile', 'chapter-106-delivery-operations', 'Routing realities, crew craft, and what the floor does to make deliveries succeed.', 106),
 ((SELECT id FROM academy_volumes WHERE vol_number=15), 107, 'Chapter 107 — The Warehouse, Returns & Reverse Logistics', 'chapter-107-warehouse-reverse-logistics', 'Receiving discipline, the returns machine, and recycling obligations.', 107),
 ((SELECT id FROM academy_volumes WHERE vol_number=15), 108, 'Chapter 108 — Merchandising: The Floor as a Selling Instrument', 'chapter-108-merchandising-fundamentals', 'Layout logic, display craft, signage, and the daily standards.', 108),
 ((SELECT id FROM academy_volumes WHERE vol_number=15), 109, 'Chapter 109 — Promotions & Floor Execution', 'chapter-109-promotions-floor-execution', 'Promo mechanics behind the scenes, event execution, and compliance.', 109),
 ((SELECT id FROM academy_volumes WHERE vol_number=15), 110, 'Chapter 110 — Service, Parts & The Repair Operation', 'chapter-110-service-parts', 'Service models, the repair flow, parts, and the service-sales alliance.', 110),
 ((SELECT id FROM academy_volumes WHERE vol_number=15), 111, 'Chapter 111 — The Store''s Money: Margins, Costs & The P&L', 'chapter-111-store-economics', 'How the store actually makes money and reading its health.', 111),
 ((SELECT id FROM academy_volumes WHERE vol_number=15), 112, 'Chapter 112 — Scheduling, Communication & The Operating Cadence', 'chapter-112-store-cadence', 'Staffing logic, communication systems, and the store''s rhythms.', 112),
 ((SELECT id FROM academy_volumes WHERE vol_number=15), 113, 'Chapter 113 — The Operations-Fluent Professional', 'chapter-113-operations-fluent-professional', 'The fluency assembled, the gate, and the bridge to leadership.', 113)
ON CONFLICT (chapter_number) DO UPDATE
SET title=EXCLUDED.title, slug=EXCLUDED.slug, intro=EXCLUDED.intro, sort_order=EXCLUDED.sort_order;

INSERT INTO academy_chapters (volume_id, chapter_number, title, slug, intro, sort_order) VALUES
 ((SELECT id FROM academy_volumes WHERE vol_number=16), 114, 'Chapter 114 — Crossing Over: From Top Seller to Sales Leader', 'chapter-114-crossing-to-leadership', 'The job that changes, the first ninety days, and the ex-peer problem.', 114),
 ((SELECT id FROM academy_volumes WHERE vol_number=16), 115, 'Chapter 115 — Hiring: Building the Floor One Decision at a Time', 'chapter-115-hiring', 'What predicts, the pipeline, and the interview craft.', 115),
 ((SELECT id FROM academy_volumes WHERE vol_number=16), 116, 'Chapter 116 — Onboarding & The 90-Day Ramp', 'chapter-116-onboarding-ramp', 'The first week, the curriculum as ramp plan, gates and ramp economics.', 116),
 ((SELECT id FROM academy_volumes WHERE vol_number=16), 117, 'Chapter 117 — The Coaching Craft: Observation, Feedback & The One-to-One', 'chapter-117-coaching-craft', 'Floor observation, the feedback formula, and the one-to-one architecture.', 117),
 ((SELECT id FROM academy_volumes WHERE vol_number=16), 118, 'Chapter 118 — Training Systems & Team Development', 'chapter-118-training-team-development', 'The huddle, the drill culture, curriculum deployment, and the bench.', 118),
 ((SELECT id FROM academy_volumes WHERE vol_number=16), 119, 'Chapter 119 — Motivation, Culture & Retention', 'chapter-119-motivation-culture-retention', 'Motivation systems, compensation stewardship, culture, and retention.', 119),
 ((SELECT id FROM academy_volumes WHERE vol_number=16), 120, 'Chapter 120 — Performance Management & The Hard Conversations', 'chapter-120-performance-management', 'Standards enforced fairly, the improvement protocol, and the respectful exit.', 120),
 ((SELECT id FROM academy_volumes WHERE vol_number=16), 121, 'Chapter 121 — Leading the Trade Desk & The Multi-Engine Floor', 'chapter-121-leading-trade-desk', 'The trade desk as a business unit and managing the specialist.', 121),
 ((SELECT id FROM academy_volumes WHERE vol_number=16), 122, 'Chapter 122 — Toward Store Leadership', 'chapter-122-store-leadership', 'The second crossing, the P&L chair, and the strategic rhythm.', 122),
 ((SELECT id FROM academy_volumes WHERE vol_number=16), 123, 'Chapter 123 — The Leader''s Scorecard & Operating Rituals', 'chapter-123-leaders-scorecard', 'The leadership dashboard, team rituals, and the leader''s own loop.', 123),
 ((SELECT id FROM academy_volumes WHERE vol_number=16), 124, 'Chapter 124 — The Summit: The Complete Professional & The Send-Off', 'chapter-124-the-summit', 'The arc reviewed, the certifications, the principles, and the charge.', 124)
ON CONFLICT (chapter_number) DO UPDATE
SET title=EXCLUDED.title, slug=EXCLUDED.slug, intro=EXCLUDED.intro, sort_order=EXCLUDED.sort_order;

CREATE TABLE IF NOT EXISTS academy_quiz_scores (
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  vol text NOT NULL,
  score int NOT NULL,
  total int NOT NULL,
  updated_at timestamptz DEFAULT now(),
  PRIMARY KEY (user_id, vol)
);
ALTER TABLE academy_quiz_scores ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "own quiz scores" ON academy_quiz_scores;
CREATE POLICY "own quiz scores" ON academy_quiz_scores
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS academy_tracks (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  track_key     TEXT UNIQUE NOT NULL,
  badge         TEXT NOT NULL,
  name          TEXT NOT NULL,
  timeline      TEXT,
  cert_name     TEXT,
  description   TEXT,
  ch_range_min  INT,
  ch_range_max  INT,
  ch_nums       INT[],
  sort_order    INT DEFAULT 0
);

INSERT INTO academy_tracks (track_key, badge, name, timeline, cert_name, description, ch_range_min, ch_range_max, sort_order) VALUES
 ('foundation',  'Track 01 · Foundation',      'New Salesperson',        'Months 0–6',   'Certified Appliance Advisor',        'The complete foundation — mindset, product knowledge, the floor process, the 90-day ramp.',            1,   8, 1),
 ('professional','Track 02 · Professional',    'Established Salesperson','Months 6–18',  'Senior Sales Professional',           'Advanced product knowledge, ACRA objections, closing techniques, attach mastery, follow-up systems.',  9,  40, 2),
 ('trade',       'Track 03 · Trade Specialist','B2B & Commercial Sales', 'Months 12+',   'Trade & Commercial Specialist',       'Builders, contractors, designers, property managers — BD, account management, and growth.',           41,  72, 3),
 ('elite',       'Track 04 · Elite',           'Top Performer',          'Months 18+',   'Elite Advisor Certification',         'Buyer psychology, archetypes, trust dynamics, closing psychology, scorecard mastery.',                73,  94, 4),
 ('leadership',  'Track 06 · Leadership',      'Sales Leader',           'Managers',     'Sales Leader Certification',          'Hiring, running the floor, managing to the scorecard, the trade desk, multi-location standards.',    103, 124, 6)
ON CONFLICT (track_key) DO UPDATE
SET name=EXCLUDED.name, timeline=EXCLUDED.timeline, cert_name=EXCLUDED.cert_name,
    description=EXCLUDED.description, ch_range_min=EXCLUDED.ch_range_min, ch_range_max=EXCLUDED.ch_range_max;

INSERT INTO academy_tracks (track_key, badge, name, timeline, cert_name, description, ch_nums, sort_order)
VALUES ('ai', 'Track 05 · Specialist', 'AI-Powered Selling', 'Cross-level', 'AI-Powered Seller Certification',
        'The AI-assisted daily workflow, comparisons, follow-up drafting, trade research, the AI Command Console.',
        ARRAY[7,95,96,97,98,99,100,101,102], 5)
ON CONFLICT (track_key) DO UPDATE SET ch_nums=EXCLUDED.ch_nums;

CREATE TABLE IF NOT EXISTS academy_track_progress (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  track_key   TEXT NOT NULL REFERENCES academy_tracks(track_key) ON DELETE CASCADE,
  started_at  TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  UNIQUE(user_id, track_key)
);

CREATE TABLE IF NOT EXISTS academy_plans (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_key      TEXT UNIQUE NOT NULL,
  name          TEXT NOT NULL,
  description   TEXT,
  price_monthly NUMERIC(10,2),
  price_annual  NUMERIC(10,2),
  min_seats     INT DEFAULT 1,
  max_seats     INT,
  features      JSONB,
  is_active     BOOLEAN DEFAULT TRUE
);

INSERT INTO academy_plans (plan_key, name, description, price_monthly, price_annual, min_seats, max_seats) VALUES
 ('course',     'Single Course',     'One volume, lifetime access',                       NULL,   297.00, 1,   1),
 ('solo',       'Academy Solo',      'Full access for one salesperson',                   197.00, 1497.00,1,   1),
 ('cohort',     'Cohort Training',   '8-week structured program, up to 10 participants',  NULL,  2500.00, 2,  10),
 ('team_3_5',   'Team 3–5 Seats',    'Per-seat licensing, 3–5 seats',                     149.00, NULL,   3,   5),
 ('team_6_10',  'Team 6–10 Seats',   'Per-seat licensing, 6–10 seats',                    129.00, NULL,   6,  10),
 ('team_11_25', 'Team 11–25 Seats',  'Per-seat licensing, 11–25 seats',                   109.00, NULL,  11,  25),
 ('ent_26_50',  'Enterprise 26–50',  'Enterprise licensing, 26–50 seats',                  89.00, NULL,  26,  50),
 ('ent_51_100', 'Enterprise 51–100', 'Enterprise licensing, 51–100 seats',                 69.00, NULL,  51, 100),
 ('ent_custom', 'Enterprise 101+',   'Custom enterprise agreement',                        NULL,  NULL, 101, NULL)
ON CONFLICT (plan_key) DO UPDATE
SET price_monthly=EXCLUDED.price_monthly, price_annual=EXCLUDED.price_annual;

CREATE TABLE IF NOT EXISTS academy_firms (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name           TEXT NOT NULL,
  slug           TEXT UNIQUE,
  plan_key       TEXT REFERENCES academy_plans(plan_key),
  seats_total    INT DEFAULT 1,
  seats_used     INT DEFAULT 0,
  owner_id       UUID REFERENCES auth.users(id),
  billing_email  TEXT,
  is_white_label BOOLEAN DEFAULT FALSE,
  white_label_name TEXT,
  status         TEXT DEFAULT 'active',
  created_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS academy_seats (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  firm_id     UUID NOT NULL REFERENCES academy_firms(id) ON DELETE CASCADE,
  user_id     UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  invited_email TEXT,
  role        TEXT DEFAULT 'member',
  status      TEXT DEFAULT 'pending',
  assigned_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(firm_id, user_id)
);

CREATE TABLE IF NOT EXISTS academy_cohorts (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name           TEXT NOT NULL,
  program        TEXT NOT NULL,
  firm_id        UUID REFERENCES academy_firms(id),
  facilitator_id UUID REFERENCES auth.users(id),
  max_participants INT DEFAULT 10,
  status         TEXT DEFAULT 'scheduled',
  start_date     DATE,
  end_date       DATE
);

CREATE TABLE IF NOT EXISTS academy_cohort_members (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cohort_id   UUID NOT NULL REFERENCES academy_cohorts(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  UNIQUE(cohort_id, user_id)
);

CREATE TABLE IF NOT EXISTS academy_certifications (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  track_key    TEXT NOT NULL REFERENCES academy_tracks(track_key),
  awarded_at   TIMESTAMPTZ DEFAULT NOW(),
  cert_number  TEXT UNIQUE DEFAULT 'AIQ-' || UPPER(SUBSTR(gen_random_uuid()::TEXT, 1, 8)),
  UNIQUE(user_id, track_key)
);

CREATE TABLE IF NOT EXISTS academy_profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name   TEXT,
  store_name  TEXT,
  role_title  TEXT,
  active_track TEXT REFERENCES academy_tracks(track_key),
  firm_id     UUID REFERENCES academy_firms(id),
  onboarded   BOOLEAN DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS mfr_vendors (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug         TEXT UNIQUE NOT NULL,
  name         TEXT NOT NULL,
  tier         TEXT,
  website      TEXT,
  logo_url     TEXT,
  status       TEXT DEFAULT 'active',
  created_at   TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS mfr_members (
  user_id      UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  vendor_id    UUID REFERENCES mfr_vendors(id) ON DELETE CASCADE,
  member_role  TEXT DEFAULT 'editor',
  created_at   TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, vendor_id)
);

CREATE TABLE IF NOT EXISTS mfr_user_roles (
  user_id      UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  is_admin     BOOLEAN DEFAULT FALSE,
  is_manufacturer BOOLEAN DEFAULT FALSE,
  is_retailer  BOOLEAN DEFAULT TRUE,
  is_builder   BOOLEAN DEFAULT FALSE,
  is_designer  BOOLEAN DEFAULT FALSE,
  created_at   TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS mfr_invites (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email        TEXT NOT NULL,
  vendor_slug  TEXT,
  vendor_name  TEXT,
  invite_role  TEXT DEFAULT 'manufacturer',
  code         TEXT UNIQUE NOT NULL,
  status       TEXT DEFAULT 'pending',
  invited_by   UUID REFERENCES auth.users(id),
  created_at   TIMESTAMPTZ DEFAULT now(),
  accepted_at  TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS mfr_assets (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id    UUID REFERENCES mfr_vendors(id) ON DELETE CASCADE,
  category     TEXT NOT NULL,
  title        TEXT NOT NULL,
  description  TEXT,
  model        TEXT,
  product_category TEXT,
  file_url     TEXT,
  external_url TEXT,
  file_type    TEXT,
  audiences    TEXT[] DEFAULT ARRAY['retailer'],
  is_published BOOLEAN DEFAULT TRUE,
  version      TEXT,
  effective_date DATE,
  expires_date DATE,
  uploaded_by  UUID REFERENCES auth.users(id),
  created_at   TIMESTAMPTZ DEFAULT now(),
  updated_at   TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_mfr_assets_vendor ON mfr_assets(vendor_id);
CREATE INDEX IF NOT EXISTS idx_mfr_assets_category ON mfr_assets(category);

ALTER TABLE mfr_vendors     ENABLE ROW LEVEL SECURITY;
ALTER TABLE mfr_members     ENABLE ROW LEVEL SECURITY;
ALTER TABLE mfr_user_roles  ENABLE ROW LEVEL SECURITY;
ALTER TABLE mfr_invites     ENABLE ROW LEVEL SECURITY;
ALTER TABLE mfr_assets      ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION is_admin() RETURNS BOOLEAN AS $$
  SELECT COALESCE((SELECT is_admin FROM mfr_user_roles WHERE user_id = auth.uid()), FALSE);
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION manages_vendor(v UUID) RETURNS BOOLEAN AS $$
  SELECT EXISTS(SELECT 1 FROM mfr_members WHERE user_id = auth.uid() AND vendor_id = v);
$$ LANGUAGE sql SECURITY DEFINER STABLE;

DROP POLICY IF EXISTS "read vendors" ON mfr_vendors;
CREATE POLICY "read vendors" ON mfr_vendors FOR SELECT USING (auth.role() = 'authenticated');
DROP POLICY IF EXISTS "admin write vendors" ON mfr_vendors;
CREATE POLICY "admin write vendors" ON mfr_vendors FOR ALL USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS "member update own vendor" ON mfr_vendors;
CREATE POLICY "member update own vendor" ON mfr_vendors FOR UPDATE USING (manages_vendor(id)) WITH CHECK (manages_vendor(id));

DROP POLICY IF EXISTS "own memberships" ON mfr_members;
CREATE POLICY "own memberships" ON mfr_members FOR SELECT USING (user_id = auth.uid() OR is_admin() OR manages_vendor(vendor_id));
DROP POLICY IF EXISTS "admin manage members" ON mfr_members;
CREATE POLICY "admin manage members" ON mfr_members FOR ALL USING (is_admin() OR manages_vendor(vendor_id)) WITH CHECK (is_admin() OR manages_vendor(vendor_id));
DROP POLICY IF EXISTS "self join membership" ON mfr_members;
CREATE POLICY "self join membership" ON mfr_members FOR INSERT WITH CHECK (user_id = auth.uid() OR is_admin());

DROP POLICY IF EXISTS "own role" ON mfr_user_roles;
CREATE POLICY "own role" ON mfr_user_roles FOR SELECT USING (user_id = auth.uid() OR is_admin());
DROP POLICY IF EXISTS "own role upsert" ON mfr_user_roles;
CREATE POLICY "own role upsert" ON mfr_user_roles FOR ALL USING (user_id = auth.uid() OR is_admin()) WITH CHECK (user_id = auth.uid() OR is_admin());

DROP POLICY IF EXISTS "admin invites" ON mfr_invites;
CREATE POLICY "admin invites" ON mfr_invites FOR ALL USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS "read invite by code" ON mfr_invites;
CREATE POLICY "read invite by code" ON mfr_invites FOR SELECT USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "read published assets" ON mfr_assets;
CREATE POLICY "read published assets" ON mfr_assets FOR SELECT USING (is_published = TRUE AND auth.role() = 'authenticated');
DROP POLICY IF EXISTS "manage own assets" ON mfr_assets;
CREATE POLICY "manage own assets" ON mfr_assets FOR ALL USING (is_admin() OR manages_vendor(vendor_id)) WITH CHECK (is_admin() OR manages_vendor(vendor_id));

INSERT INTO mfr_vendors (slug, name, tier, website) VALUES
 ('bosch','Bosch','Premium','https://www.bosch-home.com/us/'),
 ('ge-appliances','GE Appliances','Value to Premium','https://www.geappliances.com/'),
 ('whirlpool','Whirlpool','Value to Mid','https://www.whirlpool.com/'),
 ('kitchenaid','KitchenAid','Premium','https://www.kitchenaid.com/'),
 ('maytag','Maytag','Value to Mid','https://www.maytag.com/'),
 ('samsung','Samsung','Value to Premium','https://www.samsung.com/us/home-appliances/'),
 ('lg','LG','Value to Premium','https://www.lg.com/us/'),
 ('frigidaire','Frigidaire','Value','https://www.frigidaire.com/'),
 ('electrolux','Electrolux','Premium','https://www.electroluxappliances.com/'),
 ('monogram','Monogram','Luxury','https://www.monogram.com/'),
 ('jennair','JennAir','Luxury','https://www.jennair.com/'),
 ('fotile','FOTILE','Premium','https://us.fotileglobal.com/'),
 ('elica','Elica','Premium','https://www.elica.com/us/'),
 ('broan','Broan','Value to Mid','https://www.broan-nutone.com/'),
 ('best','Best','Premium','https://www.bestrangehoods.com/'),
 ('venmar','Venmar','Value to Mid','https://www.venmar.ca/'),
 ('danby','Danby','Value','https://www.danby.com/'),
 ('sharp','Sharp','Value to Mid','https://www.sharpusa.com/'),
 ('panasonic','Panasonic','Value to Mid','https://www.panasonic.com/us/')
ON CONFLICT (slug) DO NOTHING;

CREATE TABLE IF NOT EXISTS ai_trainer_sessions (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  chapter_slug TEXT NOT NULL,
  course       TEXT,
  module       TEXT,
  lesson       TEXT,
  created_at   TIMESTAMPTZ DEFAULT now(),
  updated_at   TIMESTAMPTZ DEFAULT now(),
  UNIQUE (user_id, chapter_slug)
);

CREATE TABLE IF NOT EXISTS ai_trainer_messages (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id   UUID REFERENCES ai_trainer_sessions(id) ON DELETE CASCADE,
  user_id      UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  msg_role     TEXT NOT NULL CHECK (msg_role IN ('user','assistant')),
  content      TEXT NOT NULL,
  created_at   TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ait_msgs_session ON ai_trainer_messages(session_id, created_at);

ALTER TABLE ai_trainer_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_trainer_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "own trainer sessions" ON ai_trainer_sessions;
CREATE POLICY "own trainer sessions" ON ai_trainer_sessions
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "own trainer messages" ON ai_trainer_messages;
CREATE POLICY "own trainer messages" ON ai_trainer_messages
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
