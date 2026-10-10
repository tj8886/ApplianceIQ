import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type JsonObject = Record<string, unknown>;
type SpecOperation = "set" | "clear" | "not_applicable";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
};

const respond = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

const cleanModel = (value: string) => value.trim().replace(/\s+/g, " ").toUpperCase();
const normalizeText = (value: unknown) => String(value ?? "").trim();
const isRecord = (value: unknown): value is JsonObject => !!value && typeof value === "object" && !Array.isArray(value);

const ALLOWED_ACTION_KEYS = new Set(["action", "productId", "originalVersion", "section", "templateId", "changes", "reason", "product", "rules", "formulaVersion", "changeRequestId", "decision", "notes", "suggestionId", "documentId", "assetId", "orderedAssetIds", "relationshipId", "targetProductId", "query", "brand", "category", "limit", "offset", "excludeProductId"]);
const GROUP_ALLOWLIST = new Set(["configuration", "dimensions", "performance", "electrical", "gas", "installation", "ventilation", "certifications", "warranty", "notes"]);
const BOOLEAN_KEYS = new Set([
  "counter_depth", "panel_ready", "ice_maker", "water_dispenser", "water_connection_required", "water_filtration", "dual_evaporator",
  "temperature_zones", "door_alarm", "sabbath_mode", "wifi", "energy_star", "third_rack", "adjustable_rack", "leak_protection",
  "convection", "induction", "air_fry", "self_clean", "steam_clean", "warming_drawer", "double_oven", "griddle", "stackable",
  "pedestal_compatible", "steam", "automatic_dispensing", "heat_pump", "reversible_door", "recirculating_support", "trim_kit_compatibility",
  "built_in_kit_required", "wet_cleaning", "mop_function", "mapping", "obstacle_avoidance", "auto_empty", "self_cleaning", "rotisserie",
  "side_burner", "weather_resistance", "cover_compatibility", "dishwasher_safe_parts", "smart_connectivity", "dedicated_circuit_required",
  "adjustable_height_range", "blender", "unknown_boolean_placeholder",
]);

const SELECT_RULES: Record<string, string[]> = {
  refrigerator_type: ["French door", "Side-by-side", "Top freezer", "Bottom freezer", "Column", "Compact"],
  configuration: ["Freestanding", "Built-in", "Integrated", "Counter-depth", "Column", "Panel-ready"],
  installation_type: ["Freestanding", "Built-in", "Integrated", "Counter-depth", "Countertop", "Portable", "Over-the-range", "Drawer", "Wall mount", "Under-cabinet", "Island", "Downdraft", "Insert"],
  door_hinge: ["Left", "Right", "Reversible", "French split"],
  door_swing: ["Left", "Right", "Reversible", "French split"],
  dishwasher_type: ["Built-in", "Portable", "Drawer", "Countertop"],
  handle_type: ["Bar", "Pocket", "Tubular", "Recessed"],
  fuel_type: ["Gas", "Electric", "Dual fuel", "Induction", "Charcoal", "Pellet"],
  cooktop_fuel_type: ["Gas", "Electric", "Dual fuel", "Induction"],
  oven_fuel_type: ["Gas", "Electric", "Dual fuel"],
  product_type: ["Range", "Cooktop", "Rangetop", "Wall oven", "Speed oven", "Warming drawer", "Combination oven", "Washer", "Dryer", "Washer dryer combo", "Grill", "Griddle", "Pizza oven", "Smoker", "Outdoor refrigerator", "Outdoor burner", "Blender", "Coffee maker", "Mixer", "Toaster", "Processor", "Kettle", "Air fryer", "Other", "Microwave"],
  load_style: ["Front load", "Top load", "Side load", "Stackable"],
  vent_type: ["Vented", "Ventless"],
  hood_type: ["Under-cabinet", "Wall mount", "Island", "Insert", "Downdraft"],
  duct_direction: ["Vertical", "Horizontal", "Convertible"],
  blower_type: ["Internal", "External", "Inline"],
  microwave_type: ["Countertop", "Over-the-range", "Built-in", "Drawer"],
  vacuum_type: ["Upright", "Canister", "Robot", "Stick", "Handheld"],
  cleaning_system: ["Bagged", "Bagless", "Hybrid"],
  bagged_or_bagless: ["Bagged", "Bagless", "Hybrid"],
  battery_type: ["Lithium-ion", "Nickel-metal hydride", "Other"],
};

const MULTI_KEYS = new Set(["wash_cycles", "dry_cycles", "included_accessories", "required_accessories", "floor_types"]);

const dimensionRegex = /(width|height|depth|cutout|clearance|adjustable_height_range|door_open|installation_depth|dock_dimensions)/i;
const numericRegex = /(capacity|place_settings|noise_level|rack_count|burner_count|element_count|oven_count|speed_count|power|runtime|charge_time|speed_settings|turntable_size|venting_cfm|maximum_cfm|minimum_cfm|cooking_area|total_btu|spin_speed|voltage|amperage|wattage|frequency|weight|annual_energy_consumption|max_cfm|min_cfm|airflow|cfm)/i;
const percentRegex = /(confidence|score)/i;
const textKeys = new Set([
  "annual_energy_consumption", "electrical_requirements", "gas_requirements", "water_requirements", "drain_requirements",
  "required_breaker", "tub_material", "drying_system", "filtration_system", "convection_type", "burner_output", "filter_type",
  "dock_dimensions", "temperature_range", "battery_type", "bagged_or_bagless", "material", "product_type", "additional_notes",
  "compatible_stacking_kit", "fuel_type", "cooktop_fuel_type", "oven_fuel_type", "installation_type", "configuration",
  "door_hinge", "door_swing", "turntable_size", "clearance_above_gas_cooking", "clearance_above_electric_cooking",
  "handle_type", "water_connection", "drain_requirements", "clearance_above_gas_cooking", "clearance_above_electric_cooking",
  "filtration", "included_accessories", "required_accessories", "warranty", "water_requirements", "minimum_clearances",
  "load_style", "vent_type", "hood_type", "duct_direction", "blower_type", "microwave_type", "vacuum_type", "cleaning_system",
  "product_type", "convection_type",
  "door_swing", "door_hinge", "hood_type", "filter_type", "material", "battery_type", "bagged_or_bagless", "electrical_requirements",
]);

const TEMPLATE_ALIASES: Record<string, string[]> = {
  refrigeration: ["refrigeration", "refrigerator", "fridge", "freezer", "wine cooler", "column refrigerator"],
  dishwashers: ["dishwasher", "dishwashers"],
  cooking: ["cooking", "range", "ranges", "cooktop", "cooktops", "rangetop", "rangetops", "wall oven", "ovens", "speed oven", "warming drawer", "combination oven"],
  laundry: ["laundry", "washer", "washers", "dryer", "dryers", "washer dryer", "laundry pair"],
  ventilation: ["ventilation", "hood", "range hood", "vent hood"],
  microwaves: ["microwave", "microwaves"],
  vacuums: ["vacuum", "vacuum cleaner", "robot vacuum"],
  outdoor: ["outdoor", "outdoor appliance", "grill", "grills", "outdoor kitchen"],
  small_appliances: ["small appliance", "small appliances", "blender", "coffee maker", "toaster", "mixer", "processor"],
  general: [],
};

const canonicalTemplateForCategory = (category: string | null | undefined) => {
  const lowered = String(category || "").toLowerCase();
  const match = Object.entries(TEMPLATE_ALIASES).find(([, aliases]) => aliases.some(alias => lowered.includes(alias)));
  return match?.[0] || "general";
};

const normalizeUnit = (unit: unknown, allowedUnits: string[] = []) => {
  if (unit == null || unit === "") return "";
  const text = String(unit).trim();
  const canonical = text.toLowerCase();
  const map = new Map<string, string>([
    ["in", "in"], ["inch", "in"], ["inches", "in"],
    ["cm", "cm"], ["centimeter", "cm"], ["centimeters", "cm"],
    ["mm", "mm"], ["millimeter", "mm"], ["millimeters", "mm"],
    ["lb", "lb"], ["lbs", "lb"], ["pound", "lb"], ["pounds", "lb"],
    ["kg", "kg"], ["kilogram", "kg"], ["kilograms", "kg"],
    ["cu ft", "cu. ft."], ["cu. ft.", "cu. ft."], ["cubic feet", "cu. ft."], ["ft3", "cu. ft."],
    ["l", "L"], ["liter", "L"], ["liters", "L"], ["litre", "L"], ["litres", "L"],
    ["v", "V"], ["volt", "V"], ["volts", "V"],
    ["a", "A"], ["amp", "A"], ["amps", "A"], ["amperage", "A"],
    ["w", "W"], ["watt", "W"], ["watts", "W"],
    ["kw", "kW"],
    ["hz", "Hz"],
    ["cfm", "CFM"],
    ["btu", "BTU"],
    ["dba", "dBA"],
    ["rpm", "rpm"],
    ["minutes", "minutes"], ["minute", "minutes"], ["min", "minutes"],
    ["hours", "hours"], ["hour", "hours"], ["hr", "hours"], ["hrs", "hours"],
    ["gallons", "gallons"], ["gallon", "gallons"], ["gal", "gallons"],
    ["sq in", "sq_in"], ["sq_in", "sq_in"],
  ]);
  const normalized = map.get(canonical) || text;
  const allowed = allowedUnits.length ? allowedUnits : [normalized];
  const match = allowed.find(candidate => String(candidate).toLowerCase() === String(normalized).toLowerCase());
  return match || normalized;
};

const allowedUnitsFor = (key: string) => {
  if (dimensionRegex.test(key)) return ["in", "cm", "mm"];
  if (/weight/i.test(key)) return ["lb", "kg"];
  if (/(capacity|place_settings)/i.test(key)) return ["cu. ft.", "L", "place settings", "bottles", "loads"];
  if (/(voltage)/i.test(key)) return ["V"];
  if (/(amperage)/i.test(key)) return ["A"];
  if (/(wattage|power)/i.test(key)) return ["W", "kW"];
  if (/(frequency)/i.test(key)) return ["Hz"];
  if (/(noise_level)/i.test(key)) return ["dBA"];
  if (/(maximum_cfm|minimum_cfm|venting_cfm|airflow|cfm)/i.test(key)) return ["CFM"];
  if (/(total_btu|burner_output)/i.test(key)) return ["BTU"];
  if (/(runtime|charge_time|speed_settings)/i.test(key)) return ["minutes", "hours"];
  if (/(cooking_area|turntable_size)/i.test(key)) return ["sq_in", "in", "cm"];
  if (/(annual_energy_consumption)/i.test(key)) return ["kWh"];
  return [];
};

const inferFieldType = (key: string, value: unknown) => {
  if (BOOLEAN_KEYS.has(key)) return "boolean";
  if (MULTI_KEYS.has(key)) return "multi-select";
  if (SELECT_RULES[key]) return "select";
  if (textKeys.has(key)) return "text";
  if (dimensionRegex.test(key)) return "measurement";
  if (percentRegex.test(key)) return "number";
  if (numericRegex.test(key)) return "number";
  if (Array.isArray(value)) return "multi-select";
  if (typeof value === "boolean") return "boolean";
  if (typeof value === "number") return "number";
  return null;
};

const validateField = (template: string, group: string, key: string, change: JsonObject) => {
  const errors: Record<string, { code: string; message: string; submittedValue?: unknown }> = {};
  const fieldId = `${group}.${key}`;
  if (!GROUP_ALLOWLIST.has(group)) {
    errors[fieldId] = { code: "unknown_group", message: "Unknown specification group." };
    return errors;
  }
  const known = BOOLEAN_KEYS.has(key) || MULTI_KEYS.has(key) || !!SELECT_RULES[key] || textKeys.has(key) || dimensionRegex.test(key) || numericRegex.test(key) || percentRegex.test(key);
  if (!known) {
    errors[fieldId] = { code: "unknown_field", message: "Unknown specification key." };
    return errors;
  }
  const operation = String(change.operation || "");
  if (!["set", "clear", "not_applicable"].includes(operation)) {
    errors[fieldId] = { code: "invalid_operation", message: "Unsupported specification operation." };
    return errors;
  }
  const fieldType = inferFieldType(key, change.value);
  if (operation === "clear" || operation === "not_applicable") return errors;
  const value = change.value;
  const unitRules = allowedUnitsFor(key);
  if (change.unit && !unitRules.length) {
    errors[fieldId] = { code: "invalid_unit", message: "This field does not accept a unit.", submittedValue: value };
    return errors;
  }
  if (fieldType === "boolean") {
    if (typeof value !== "boolean") errors[fieldId] = { code: "invalid_type", message: "Boolean values must be true or false.", submittedValue: value };
    return errors;
  }
  if (fieldType === "multi-select") {
    if (!Array.isArray(value)) errors[fieldId] = { code: "invalid_type", message: "Multi-select values must be an array.", submittedValue: value };
    return errors;
  }
  if (fieldType === "number" || fieldType === "measurement") {
    const numeric = typeof value === "number" ? value : Number(value);
    if (!Number.isFinite(numeric)) {
      errors[fieldId] = { code: "invalid_type", message: "Enter a numeric value.", submittedValue: value };
      return errors;
    }
    if (numeric < 0) {
      errors[fieldId] = { code: "invalid_range", message: "Numeric values cannot be negative.", submittedValue: value };
      return errors;
    }
    if (percentRegex.test(key) && numeric > 100) {
      errors[fieldId] = { code: "invalid_range", message: "Percentage values cannot exceed 100.", submittedValue: value };
      return errors;
    }
    const unit = normalizeUnit(change.unit, unitRules);
    if (change.unit && unitRules.length && !unitRules.includes(unit)) {
      errors[fieldId] = { code: "invalid_unit", message: `Allowed units: ${unitRules.join(", ")}.`, submittedValue: value };
      return errors;
    }
    return errors;
  }
  if (SELECT_RULES[key]) {
    if (typeof value !== "string" || !SELECT_RULES[key].includes(value)) {
      errors[fieldId] = { code: "invalid_value", message: "Choose one of the allowed values.", submittedValue: value };
    }
    return errors;
  }
  if (fieldType === null) {
    errors[fieldId] = { code: "unknown_field", message: "Unknown specification key.", submittedValue: value };
    return errors;
  }
  if (typeof value === "string") {
    const unit = normalizeUnit(change.unit, unitRules);
    if (change.unit && unitRules.length && !unitRules.includes(unit)) {
      errors[fieldId] = { code: "invalid_unit", message: `Allowed units: ${unitRules.join(", ")}.`, submittedValue: value };
    }
    return errors;
  }
  if (Array.isArray(value)) return errors;
  errors[fieldId] = { code: "invalid_type", message: "Unsupported specification value.", submittedValue: value };
  return errors;
};

const mergeSpecValue = (existing: unknown, change: JsonObject, key: string) => {
  const operation = String(change.operation);
  if (operation === "clear") return undefined;
  if (operation === "not_applicable") return { value: null, status: "not_applicable" };
  const fieldType = inferFieldType(key, change.value);
  const allowedUnits = allowedUnitsFor(key);
  const unit = change.unit ? normalizeUnit(change.unit, allowedUnits) : "";
  if (fieldType === "boolean") return !!change.value;
  if (fieldType === "multi-select") return Array.isArray(change.value) ? change.value : [];
  if (fieldType === "number" || fieldType === "measurement") {
    const numeric = typeof change.value === "number" ? change.value : Number(change.value);
    return unit ? { value: numeric, unit } : numeric;
  }
  if (change.unit && unit) return { value: change.value, unit };
  return change.value;
};

const mergeSpecGroups = (current: JsonObject, changes: JsonObject) => {
  const next = { ...current };
  for (const [group, groupChanges] of Object.entries(changes)) {
    const existingGroup = isRecord(next[group]) ? { ...(next[group] as JsonObject) } : {};
    for (const [key, change] of Object.entries(groupChanges as JsonObject)) {
      if (!isRecord(change)) continue;
      const merged = mergeSpecValue(existingGroup[key], change, key);
      if (change.operation === "clear") delete existingGroup[key];
      else existingGroup[key] = merged;
    }
    next[group] = existingGroup;
  }
  return next;
};

const rowToSpecGroups = (row: JsonObject | null) => ({
  dimensions: isRecord(row?.dimensions) ? row!.dimensions : {},
  electrical: isRecord(row?.electrical) ? row!.electrical : {},
  gas: isRecord(row?.gas) ? row!.gas : {},
  ventilation: isRecord(row?.ventilation) ? row!.ventilation : {},
  installation: isRecord(row?.installation) ? row!.installation : {},
  performance: isRecord(row?.performance) ? row!.performance : {},
  certifications: isRecord(row?.certifications) ? row!.certifications : {},
  warranty: isRecord(row?.warranty) ? row!.warranty : {},
  documents: isRecord(row?.documents) ? row!.documents : {},
  notes: isRecord(row?.notes) ? row!.notes : {},
});

const specGroupsToRow = (groups: JsonObject) => ({
  dimensions: groups.dimensions ?? {},
  electrical: groups.electrical ?? {},
  gas: groups.gas ?? {},
  ventilation: groups.ventilation ?? {},
  installation: groups.installation ?? {},
  performance: groups.performance ?? {},
  certifications: groups.certifications ?? {},
  warranty: groups.warranty ?? {},
  documents: groups.documents ?? {},
  notes: groups.notes ?? {},
});

const audit = async (db: ReturnType<typeof createClient>, product: JsonObject, action: string, oldRecord: unknown, newRecord: unknown, reason?: string, actorId?: string, entityType = "aiq_products", entityId?: string | null) =>
  db.from("product_iq_governance_audit_log").insert({
    organization_id: product.organization_id,
    product_id: product.id,
    entity_type: entityType,
    entity_id: entityId ?? product.id,
    action,
    actor_id: actorId,
    actor_kind: "service",
    reason,
    old_record: oldRecord,
    new_record: newRecord,
  });

const DOCUMENT_TYPES = new Map([
  ["owner_manual", "Owner Manual"],
  ["installation_guide", "Installation Guide"],
  ["warranty", "Warranty"],
  ["energy_guide", "Energy Guide"],
  ["quick_start_guide", "Quick Start Guide"],
  ["specification_sheet", "Specification Sheet"],
  ["dimension_sheet", "Dimension Sheet"],
  ["parts_list", "Parts List"],
  ["service_manual", "Service Manual"],
  ["cad", "CAD"],
  ["marketing", "Marketing"],
  ["video", "Video"],
  ["other", "Other"],
]);

const IMAGE_TYPES = new Map([
  ["hero", "Hero"],
  ["gallery", "Gallery"],
  ["lifestyle", "Lifestyle"],
  ["cutout", "Cutout"],
  ["dimension_drawing", "Dimension Drawing"],
  ["installation", "Installation"],
  ["marketing", "Marketing"],
  ["packaging", "Packaging"],
  ["thumbnail", "Thumbnail"],
  ["other", "Other"],
]);

const PUBLICATION_STATES = new Set(["draft", "submitted", "in_review", "changes_requested", "approved", "published"]);
const SOURCE_STATES = new Set(["internal", "manufacturer_submitted", "raw_import", "ai_extracted", "ai_suggested", "aiq_reviewed"]);

const RELATIONSHIP_TYPES = new Map([
  ["accessory", "Accessory"],
  ["required_accessory", "Required Accessory"],
  ["optional_accessory", "Optional Accessory"],
  ["compatible_with", "Compatible With"],
  ["incompatible_with", "Incompatible With"],
  ["replaces", "Replaces"],
  ["replaced_by", "Replaced By"],
  ["predecessor", "Predecessor"],
  ["successor", "Successor"],
  ["package_companion", "Package Companion"],
  ["installation_dependency", "Installation Dependency"],
  ["pedestal", "Pedestal"],
  ["stacking_kit", "Stacking Kit"],
  ["panel", "Panel"],
  ["handle", "Handle"],
  ["trim_kit", "Trim Kit"],
  ["filter", "Filter"],
  ["hose", "Hose"],
  ["power_cord", "Power Cord"],
  ["ventilation_dependency", "Ventilation Dependency"],
  ["cooking_dependency", "Cooking Dependency"],
  ["laundry_pair", "Laundry Pair"],
  ["refrigeration_pair", "Refrigeration Pair"],
  ["outdoor_pair", "Outdoor Pair"],
  ["alternate_finish", "Alternate Finish"],
  ["equivalent_model", "Equivalent Model"],
  ["service_part", "Service Part"],
  ["other", "Other"],
]);

const RELATIONSHIP_ALIAS_MAP: Record<string, string> = {
  accessory: "accessory",
  accessories: "accessory",
  required: "required_accessory",
  required_accessory: "required_accessory",
  optional: "optional_accessory",
  optional_accessory: "optional_accessory",
  compatible: "compatible_with",
  compatible_with: "compatible_with",
  incompatible: "incompatible_with",
  incompatible_with: "incompatible_with",
  replaces: "replaces",
  replaced_by: "replaced_by",
  predecessor: "predecessor",
  successor: "successor",
  package: "package_companion",
  package_companion: "package_companion",
  installation_dependency: "installation_dependency",
  pedestal: "pedestal",
  stacking_kit: "stacking_kit",
  panel: "panel",
  handle: "handle",
  trim_kit: "trim_kit",
  filter: "filter",
  hose: "hose",
  power_cord: "power_cord",
  ventilation_dependency: "ventilation_dependency",
  cooking_dependency: "cooking_dependency",
  laundry_pair: "laundry_pair",
  refrigeration_pair: "refrigeration_pair",
  outdoor_pair: "outdoor_pair",
  alternate_finish: "alternate_finish",
  equivalent_model: "equivalent_model",
  service_part: "service_part",
  other: "other",
};

const BIDIRECTIONAL_RELATIONSHIP_TYPES = new Set([
  "compatible_with",
  "incompatible_with",
  "package_companion",
  "laundry_pair",
  "refrigeration_pair",
  "outdoor_pair",
  "alternate_finish",
  "equivalent_model",
]);

const RELATIONSHIP_REQUIREMENT_LEVELS = new Set(["required", "recommended", "optional", "not_applicable"]);
const RELATIONSHIP_COMPATIBILITY_STATUS = new Set(["verified", "likely", "conditional", "incompatible", "unverified", "discontinued", "not_applicable"]);
const RELATIONSHIP_DIRECTION_TYPES = new Set(["forward", "bidirectional"]);
const RELATIONSHIP_CATEGORY_GROUPS: Record<string, string[]> = {
  refrigeration: ["panel", "handle", "filter", "trim_kit", "refrigeration_pair", "installation_dependency", "power_cord"],
  laundry: ["laundry_pair", "pedestal", "stacking_kit", "hose", "power_cord", "ventilation_dependency", "installation_dependency"],
  cooking: ["ventilation_dependency", "trim_kit", "handle", "power_cord", "cooking_dependency", "installation_dependency"],
  dishwashers: ["panel", "handle", "hose", "power_cord", "installation_dependency"],
  ventilation: ["cooking_dependency", "ventilation_dependency", "trim_kit", "installation_dependency"],
  microwaves: ["trim_kit", "installation_dependency", "cooking_dependency", "ventilation_dependency"],
  vacuums: ["service_part", "other", "equivalent_model"],
  outdoor: ["outdoor_pair", "installation_dependency", "power_cord", "hose"],
  small_appliances: ["service_part", "other", "equivalent_model"],
  general: ["accessory", "compatible_with", "other"],
};

const normalizeRelationshipKey = (value: unknown) => {
  const text = String(value ?? "").trim().toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
  return RELATIONSHIP_ALIAS_MAP[text] || text;
};

const relationshipLabel = (value: unknown) => RELATIONSHIP_TYPES.get(normalizeRelationshipKey(value)) || "Other";
const relationshipDirectionFor = (type: string, requestedDirection?: unknown) => {
  const canonical = normalizeRelationshipKey(type);
  const defaultDirection = BIDIRECTIONAL_RELATIONSHIP_TYPES.has(canonical) ? "bidirectional" : "forward";
  const requested = String(requestedDirection ?? "").trim().toLowerCase();
  if (!requested) return defaultDirection;
  if (!RELATIONSHIP_DIRECTION_TYPES.has(requested)) return null;
  if (defaultDirection === "bidirectional" && requested !== "bidirectional") return null;
  if (defaultDirection === "forward" && requested !== "forward") return null;
  return requested;
};

const normalizeChoice = (value: unknown, allowed: Map<string, string> | Set<string>) => {
  const text = String(value ?? "").trim();
  const key = text.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
  if (allowed instanceof Map) return allowed.get(key) ?? text;
  return allowed.has(text) ? text : key;
};

const loadProductForMutation = async (db: ReturnType<typeof createClient>, productId: string) => {
  const { data: product, error } = await db.from("aiq_products").select("*").eq("id", productId).maybeSingle();
  if (error || !product) return { error: error?.message || "Product not found", status: 404 };
  const allowed = await db.rpc("product_iq_can_manage_product", { p_organization_id: product.organization_id, p_brand_name: product.brand_name });
  if (!allowed.data) return { error: "Product IQ edit access required", status: 403 };
  return { product };
};

const touchProductForVersion = async (db: ReturnType<typeof createClient>, productId: string, versionNumber: number, userId: string, extra: JsonObject = {}) => {
  const { data: updated, error } = await db.from("aiq_products").update({ updated_by: userId, updated_at: new Date().toISOString(), ...extra }).eq("id", productId).eq("version_number", versionNumber).select("*").maybeSingle();
  if (error) return { error: error.message, status: 400 };
  if (!updated) return { conflict: true };
  return { updated };
};

const documentFieldErrors = (fields: Record<string, { code: string; message: string; submittedValue?: unknown }>) => Object.keys(fields).length ? { error: "validation_failed", code: "validation_failed", fieldErrors: fields } : null;

const normalizeDocumentType = (value: unknown) => DOCUMENT_TYPES.get(String(value ?? "").trim().toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "")) ?? null;
const normalizeImageType = (value: unknown) => IMAGE_TYPES.get(String(value ?? "").trim().toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "")) ?? null;

const DOCUMENT_ALLOWED_FIELDS = new Set(["title", "document_type", "language", "version", "source_type", "source_reference", "description", "public_visible", "approval_status"]);
const IMAGE_ALLOWED_FIELDS = new Set(["title", "image_type", "alt_text", "display_order", "source_type", "source_reference", "is_published", "is_primary"]);

const validateText = (value: unknown, field: string, required = false, max = 256) => {
  const text = normalizeText(value);
  if (!text && required) return { code: "required", message: `${field} is required.` };
  if (text.length > max) return { code: "too_long", message: `${field} must be ${max} characters or fewer.` };
  return null;
};

const validateDocChanges = (changes: JsonObject) => {
  const errors: Record<string, { code: string; message: string; submittedValue?: unknown }> = {};
  for (const key of Object.keys(changes)) {
    if (!DOCUMENT_ALLOWED_FIELDS.has(key)) {
      errors[key] = { code: "unknown_field", message: "This document field cannot be edited." };
    }
  }
  const titleError = validateText(changes.title, "Document title", true, 256);
  if (titleError) errors.title = titleError;
  const type = normalizeDocumentType(changes.document_type);
  if (!type) errors.document_type = { code: "invalid_value", message: `Document type must be one of: ${[...DOCUMENT_TYPES.values()].join(", ")}.` };
  const sourceType = String(changes.source_type ?? "").trim();
  if (sourceType && !SOURCE_STATES.has(sourceType)) errors.source_type = { code: "invalid_value", message: `Source must be one of: ${[...SOURCE_STATES].join(", ")}.` };
  const approval = String(changes.approval_status ?? "").trim();
  if (approval && !PUBLICATION_STATES.has(approval)) errors.approval_status = { code: "invalid_value", message: `Publication state must be one of: ${[...PUBLICATION_STATES].join(", ")}.` };
  const language = normalizeText(changes.language);
  if (language && language.length > 20) errors.language = { code: "too_long", message: "Language must be 20 characters or fewer." };
  const version = normalizeText(changes.version);
  if (version && version.length > 64) errors.version = { code: "too_long", message: "Version must be 64 characters or fewer." };
  const sourceReference = normalizeText(changes.source_reference);
  if (sourceReference && sourceReference.length > 128) errors.source_reference = { code: "too_long", message: "Source reference must be 128 characters or fewer." };
  const description = normalizeText(changes.description);
  if (description && description.length > 1000) errors.description = { code: "too_long", message: "Internal description must be 1000 characters or fewer." };
  return { errors, type };
};

const validateImageChanges = (changes: JsonObject) => {
  const errors: Record<string, { code: string; message: string; submittedValue?: unknown }> = {};
  for (const key of Object.keys(changes)) {
    if (!IMAGE_ALLOWED_FIELDS.has(key)) {
      errors[key] = { code: "unknown_field", message: "This image field cannot be edited." };
    }
  }
  const titleError = validateText(changes.title, "Image title", true, 256);
  if (titleError) errors.title = titleError;
  const type = normalizeImageType(changes.image_type);
  if (!type) errors.image_type = { code: "invalid_value", message: `Image type must be one of: ${[...IMAGE_TYPES.values()].join(", ")}.` };
  const altText = normalizeText(changes.alt_text);
  if (altText && altText.length > 500) errors.alt_text = { code: "too_long", message: "Alt text must be 500 characters or fewer." };
  const sourceType = String(changes.source_type ?? "").trim();
  if (sourceType && !SOURCE_STATES.has(sourceType)) errors.source_type = { code: "invalid_value", message: `Source must be one of: ${[...SOURCE_STATES].join(", ")}.` };
  const sourceReference = normalizeText(changes.source_reference);
  if (sourceReference && sourceReference.length > 128) errors.source_reference = { code: "too_long", message: "Source reference must be 128 characters or fewer." };
  const displayOrder = changes.display_order;
  if (displayOrder != null && displayOrder !== "") {
    const n = Number(displayOrder);
    if (!Number.isInteger(n) || n < 0) errors.display_order = { code: "invalid_value", message: "Display order must be a non-negative integer." };
  }
  return { errors, type };
};

const validateRelationshipChanges = (changes: JsonObject, relationshipType: string, currentSourceId?: string) => {
  const errors: Record<string, { code: string; message: string; submittedValue?: unknown }> = {};
  const allowed = new Set([
    "relationship_type",
    "direction",
    "requirement_level",
    "compatibility_status",
    "compatibility_notes",
    "installation_notes",
    "quantity",
    "minimum_quantity",
    "maximum_quantity",
    "same_brand_requirement",
    "compatible_finish_requirement",
    "source_type",
    "source_reference",
    "source_confidence",
    "effective_start_date",
    "effective_end_date",
    "notes",
    "relationship_label",
  ]);
  for (const key of Object.keys(changes)) {
    if (!allowed.has(key)) errors[key] = { code: "unknown_field", message: "This relationship field cannot be edited." };
  }

  const normalizedType = normalizeRelationshipKey(relationshipType || changes.relationship_type);
  if (!RELATIONSHIP_TYPES.has(normalizedType)) {
    errors.relationship_type = { code: "invalid_value", message: `Relationship type must be one of: ${[...RELATIONSHIP_TYPES.values()].join(", ")}.` };
  }
  const direction = relationshipDirectionFor(normalizedType, changes.direction);
  if (!direction) {
    errors.direction = { code: "invalid_value", message: "Relationship direction does not match the selected relationship type." };
  }

  const requirementLevel = String(changes.requirement_level ?? "").trim().toLowerCase();
  if (requirementLevel && !RELATIONSHIP_REQUIREMENT_LEVELS.has(requirementLevel)) {
    errors.requirement_level = { code: "invalid_value", message: `Requirement level must be one of: ${[...RELATIONSHIP_REQUIREMENT_LEVELS].join(", ")}.` };
  }
  const compatibilityStatus = String(changes.compatibility_status ?? "").trim().toLowerCase();
  if (compatibilityStatus && !RELATIONSHIP_COMPATIBILITY_STATUS.has(compatibilityStatus)) {
    errors.compatibility_status = { code: "invalid_value", message: `Compatibility status must be one of: ${[...RELATIONSHIP_COMPATIBILITY_STATUS].join(", ")}.` };
  }
  if (compatibilityStatus === "conditional" && !normalizeText(changes.compatibility_notes)) {
    errors.compatibility_notes = { code: "required", message: "Conditional compatibility requires notes." };
  }

  const quantityFields: Array<[string, number | null | undefined]> = [
    ["quantity", changes.quantity as number | null | undefined],
    ["minimum_quantity", changes.minimum_quantity as number | null | undefined],
    ["maximum_quantity", changes.maximum_quantity as number | null | undefined],
  ];
  for (const [key, value] of quantityFields) {
    if (value == null || value === "") continue;
    const n = Number(value);
    if (!Number.isInteger(n) || n <= 0) errors[key] = { code: "invalid_value", message: `${key.replaceAll("_", " ")} must be a positive integer.`, submittedValue: value };
  }
  const minQty = changes.minimum_quantity == null || changes.minimum_quantity === "" ? null : Number(changes.minimum_quantity);
  const maxQty = changes.maximum_quantity == null || changes.maximum_quantity === "" ? null : Number(changes.maximum_quantity);
  if (minQty != null && maxQty != null && Number.isInteger(minQty) && Number.isInteger(maxQty) && minQty > maxQty) {
    errors.minimum_quantity = { code: "invalid_value", message: "Minimum quantity cannot exceed maximum quantity." };
    errors.maximum_quantity = { code: "invalid_value", message: "Maximum quantity must be at least minimum quantity." };
  }

  if (normalizedType && ["compatible_with", "incompatible_with", "alternate_finish", "equivalent_model", "package_companion", "laundry_pair", "refrigeration_pair", "outdoor_pair"].includes(normalizedType)) {
    if (changes.quantity != null && String(changes.quantity) !== "") {
      errors.quantity = { code: "invalid_value", message: "This relationship type does not use a quantity." };
    }
  }
  if (normalizedType === "incompatible_with" && (changes.quantity != null || changes.minimum_quantity != null || changes.maximum_quantity != null)) {
    errors.quantity = { code: "invalid_value", message: "Incompatible relationships cannot specify quantities." };
  }
  if (normalizedType === "required_accessory" && changes.quantity != null && Number(changes.quantity) < 1) {
    errors.quantity = { code: "invalid_value", message: "Required accessories must have a positive quantity." };
  }

  const sourceConfidence = changes.source_confidence;
  if (sourceConfidence != null && String(sourceConfidence) !== "") {
    const n = Number(sourceConfidence);
    if (!Number.isFinite(n) || n < 0 || n > 100) errors.source_confidence = { code: "invalid_value", message: "Source confidence must be between 0 and 100." };
  }
  if (changes.source_type != null && normalizeText(changes.source_type) && !SOURCE_STATES.has(normalizeText(changes.source_type))) {
    errors.source_type = { code: "invalid_value", message: `Source must be one of: ${[...SOURCE_STATES].join(", ")}.` };
  }

  const start = normalizeText(changes.effective_start_date);
  const end = normalizeText(changes.effective_end_date);
  if (start && Number.isNaN(Date.parse(start))) errors.effective_start_date = { code: "invalid_value", message: "Effective start date must be a valid date." };
  if (end && Number.isNaN(Date.parse(end))) errors.effective_end_date = { code: "invalid_value", message: "Effective end date must be a valid date." };
  if (start && end && !Number.isNaN(Date.parse(start)) && !Number.isNaN(Date.parse(end)) && new Date(end) < new Date(start)) {
    errors.effective_start_date = { code: "invalid_value", message: "Effective end date cannot precede start date." };
    errors.effective_end_date = { code: "invalid_value", message: "Effective end date cannot precede start date." };
  }

  if (currentSourceId && normalizeText(changes.related_product_id) && String(changes.related_product_id) === currentSourceId) {
    errors.related_product_id = { code: "self_reference", message: "A product cannot be related to itself." };
  }

  return { errors, normalizedType, direction };
};

const cloneRecord = (value: unknown) => JSON.parse(JSON.stringify(value ?? null));

Deno.serve(async req => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return respond({ error: "Method not allowed" }, 405);

  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return respond({ error: "Authentication required" }, 401);

  const url = Deno.env.get("SUPABASE_URL") || "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") || "";
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (!url || !anon || !service) return respond({ error: "Server configuration missing" }, 500);

  const userClient = createClient(url, anon, { global: { headers: { Authorization: `Bearer ${token}` } } });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return respond({ error: "Invalid session" }, 401);

  const db = createClient(url, service, { auth: { persistSession: false } });
  const { data: role } = await db.from("product_iq_platform_roles").select("role,status,expires_at").eq("user_id", user.id).maybeSingle();
  if (!role || role.status !== "active" || (role.expires_at && new Date(role.expires_at) <= new Date())) {
    return respond({ error: "Product IQ administrator access required" }, 403);
  }

  const body = await req.json().catch(() => null);
  if (!isRecord(body) || !body.action) return respond({ error: "action is required" }, 400);
  const unexpected = Object.keys(body).filter(key => !ALLOWED_ACTION_KEYS.has(key));
  if (unexpected.length) return respond({ error: "Unknown request fields", code: "validation_failed", fieldErrors: Object.fromEntries(unexpected.map(key => [key, { code: "unknown_field", message: "This field is not allowed in this request." }])) }, 400);

  if (body.action === "search_relationship_products") {
    const query = normalizeText(body.query);
    const brand = normalizeText(body.brand);
    const category = normalizeText(body.category);
    const limit = Math.min(Math.max(Number(body.limit) || 12, 1), 40);
    const offset = Math.max(Number(body.offset) || 0, 0);
    const excludeProductId = normalizeText(body.excludeProductId);
    let search = userClient.from("aiq_products").select("id,manufacturer_name,brand_name,model,short_description,category,status,approval_status,public_visible,version_number,updated_at", { count: "exact" }).order("updated_at", { ascending: false });
    if (query) {
      const normalized = cleanModel(query);
      search = search.or(`model.ilike.%${query}%,short_description.ilike.%${query}%,brand_name.ilike.%${query}%,model.ilike.%${normalized}%`);
    }
    if (brand) search = search.ilike("brand_name", `%${brand}%`);
    if (category) search = search.ilike("category", `%${category}%`);
    if (excludeProductId) search = search.neq("id", excludeProductId);
    const { data: products, error, count } = await search.range(offset, offset + limit - 1);
    if (error) return respond({ error: error.message }, 400);
    const ids = (products || []).map(row => String(row.id));
    let primaryImageMap: Record<string, JsonObject> = {};
    if (ids.length) {
      const { data: images } = await userClient.from("mfr_assets").select("product_id,file_url,media_url,title,image_type,is_primary").in("product_id", ids).eq("is_primary", true).is("archived_at", null);
      primaryImageMap = Object.fromEntries((images || []).map(row => [String(row.product_id), row]));
    }
    return respond({
      data: (products || []).map(row => ({
        ...row,
        primary_image_url: primaryImageMap[String(row.id)]?.file_url || primaryImageMap[String(row.id)]?.media_url || null,
        primary_image_title: primaryImageMap[String(row.id)]?.title || null,
        primary_image_type: primaryImageMap[String(row.id)]?.image_type || null,
      })),
      count: count ?? products?.length ?? 0,
    });
  }

  if (body.action === "create_product") {
    const p = isRecord(body.product) ? body.product : {};
    const required = ["manufacturer_name", "brand_name", "model", "short_description", "category", "status", "source_type", "source_reference"];
    const missing = required.filter(k => !String(p[k] ?? "").trim());
    if (missing.length) return respond({ error: "Missing required fields", fields: missing }, 400);
    const model = cleanModel(String(p.model));
    const { data: duplicate } = await db.from("aiq_products").select("id").ilike("brand_name", String(p.brand_name).trim()).ilike("model", model).limit(1);
    if (duplicate?.length) return respond({ error: "A matching brand and model already exists", code: "duplicate_model" }, 409);
    const { data, error } = await db.from("aiq_products").insert({
      ...p,
      model,
      status: p.status || "draft",
      approval_status: "draft",
      public_visible: false,
      created_by: user.id,
      updated_by: user.id,
      source_confidence: p.source_confidence ?? null,
    }).select().single();
    if (error) return respond({ error: error.message }, 400);
    await audit(db, data as JsonObject, "product_draft_created", null, data, "Governed Product IQ draft creation", user.id);
    return respond({ data }, 201);
  }

  if (body.action === "update_product") {
    const { productId, originalVersion, section, changes, reason } = body as JsonObject;
    if (!productId || !Number.isInteger(originalVersion) || !section || !isRecord(changes)) return respond({ error: "productId, originalVersion, section, and changes are required" }, 400);
    const protectedFields = new Set(["approval_status", "public_visible", "published_at", "unpublished_at", "organization_id", "manufacturer_id", "brand_id", "created_by", "updated_by", "version_number"]);
    const overviewFields = new Set(["short_description", "model", "category", "status", "source_type", "source_reference", "source_confidence", "country_availability"]);
    if (Object.keys(changes).some(key => protectedFields.has(key))) return respond({ error: "Protected fields require a review transition", code: "protected_field" }, 403);
    if (section === "overview" && Object.keys(changes).some(key => !overviewFields.has(key))) return respond({ error: "Unknown or non-overview field", code: "unknown_field" }, 400);
    if (section === "overview" && ["short_description", "model", "category"].some(key => key in changes && !String((changes as JsonObject)[key] ?? "").trim())) return respond({ error: "Product name, model number, and category are required", code: "validation_failed" }, 400);
    if ("source_confidence" in changes && (Number((changes as JsonObject).source_confidence) < 0 || Number((changes as JsonObject).source_confidence) > 100 || Number.isNaN(Number((changes as JsonObject).source_confidence)))) {
      return respond({ error: "Confidence must be between 0 and 100", code: "validation_failed" }, 400);
    }
    const { data: current, error: readError } = await db.from("aiq_products").select("*").eq("id", String(productId)).maybeSingle();
    if (readError || !current) return respond({ error: "Product not found" }, 404);
    if (current.version_number !== originalVersion) {
      return respond({
        error: "This product has a newer version. Reload before saving.",
        code: "conflict",
        currentVersion: current.version_number,
        submittedVersion: originalVersion,
        updatedAt: current.updated_at,
        updatedBy: current.updated_by,
      }, 409);
    }
    if ((changes as JsonObject).model) {
      (changes as JsonObject).model = cleanModel(String((changes as JsonObject).model));
      const { data: dupe } = await db.from("aiq_products").select("id").ilike("brand_name", String(current.brand_name)).ilike("model", String((changes as JsonObject).model)).neq("id", String(productId)).limit(1);
      if (dupe?.length) return respond({ error: "A matching brand and model already exists", code: "duplicate_model" }, 409);
    }
    const { data: updated, error: updateError } = await db.from("aiq_products").update({ ...changes, updated_by: user.id }).eq("id", String(productId)).eq("version_number", originalVersion).select().single();
    if (updateError || !updated) return respond({ error: updateError?.message || "Update conflict", code: "conflict", currentVersion: current.version_number }, 409);
    await audit(db, updated as JsonObject, "product_section_updated", current, updated, `${section}: ${reason || "governed update"}`, user.id);
    return respond({ data: updated });
  }

  if (body.action === "validate_product") {
    const { productId, rules, formulaVersion = "phase3.v1" } = body as JsonObject;
    const { data: p } = await db.from("aiq_products").select("*").eq("id", String(productId)).maybeSingle();
    const { data: s } = await db.from("aiq_product_specifications").select("*").eq("product_id", String(productId)).maybeSingle();
    if (!p) return respond({ error: "Product not found" }, 404);
    const issues = (Array.isArray(rules) ? rules : []).filter((r: any) => r.required && !r.value).map((r: any) => ({
      origin: "deterministic",
      rule_id: r.id,
      rule_version: formulaVersion,
      section: r.section,
      key: r.key,
      issue_type: "missing_required_specification",
      severity: "blocking",
      current_value: null,
      explanation: `${r.label} is required for ${p.category}.`,
      suggested_action: "Add a value in the governed workspace.",
    }));
    const score = Math.max(0, 100 - issues.length * 10);
    const result = {
      organization_id: p.organization_id,
      product_id: p.id,
      version_number: p.version_number,
      score,
      section_scores: { formula_version: formulaVersion, completeness: score },
      issues,
      validation_source: "rules",
      validated_by: user.id,
    };
    const { data, error } = await db.from("product_iq_data_quality_results").upsert(result, { onConflict: "product_id,version_number,validation_source" }).select().single();
    return error ? respond({ error: error.message }, 400) : respond({ data, specification_present: !!s });
  }

  if (body.action === "update_specifications") {
    const { productId, originalVersion, templateId, changes, reason, section } = body as JsonObject;
    if (!productId || !Number.isInteger(originalVersion) || !templateId || !isRecord(changes)) return respond({ error: "productId, originalVersion, templateId, and changes are required" }, 400);
    if (section && section !== "specifications") return respond({ error: "Invalid section for specification update", code: "validation_failed" }, 400);

    const { data: product } = await db.from("aiq_products").select("*").eq("id", String(productId)).maybeSingle();
    if (!product) return respond({ error: "Product not found" }, 404);
    const resolvedTemplate = canonicalTemplateForCategory(product.category);
    if (String(templateId) && canonicalTemplateForCategory(String(templateId)) !== resolvedTemplate && String(templateId) !== resolvedTemplate) {
      // The browser supplied a template id, but the server resolves the authoritative family.
      return respond({ error: "Unknown specification template", code: "unknown_template" }, 400);
    }
    if (product.version_number !== originalVersion) {
      return respond({
        error: "This product has a newer version. Reload before saving.",
        code: "conflict",
        currentVersion: product.version_number,
        submittedVersion: originalVersion,
        updatedAt: product.updated_at,
        updatedBy: product.updated_by,
      }, 409);
    }

    const fieldErrors: Record<string, { code: string; message: string; submittedValue?: unknown }> = {};
    const nextChanges: JsonObject = {};
    for (const [group, groupChangesRaw] of Object.entries(changes)) {
      if (!GROUP_ALLOWLIST.has(group)) {
        fieldErrors[group] = { code: "unknown_group", message: "Unknown specification group." };
        continue;
      }
      if (!isRecord(groupChangesRaw)) {
        fieldErrors[group] = { code: "invalid_group", message: "Specification group changes must be an object." };
        continue;
      }
      const groupChanges: JsonObject = {};
      for (const [key, changeRaw] of Object.entries(groupChangesRaw)) {
        if (!isRecord(changeRaw)) {
          fieldErrors[`${group}.${key}`] = { code: "invalid_field", message: "Each specification change must be an object." };
          continue;
        }
        if (!("operation" in changeRaw)) {
          fieldErrors[`${group}.${key}`] = { code: "invalid_operation", message: "Specification changes require an explicit operation." };
          continue;
        }
        const change = changeRaw as JsonObject;
        const allowed = validateField(resolvedTemplate, group, key, change);
        Object.assign(fieldErrors, allowed);
        if (allowed[`${group}.${key}`]) continue;
        const op = String(change.operation) as SpecOperation;
        if (op === "clear" || op === "not_applicable" || op === "set") groupChanges[key] = change;
      }
      if (Object.keys(groupChanges).length) nextChanges[group] = groupChanges;
    }
    if (Object.keys(fieldErrors).length) {
      return respond({ error: "validation_failed", code: "validation_failed", fieldErrors }, 400);
    }
    if (!Object.keys(nextChanges).length) {
      return respond({ error: "No specification changes were supplied", code: "no_changes" }, 400);
    }

    const { data: existingSpec } = await db.from("aiq_product_specifications").select("*").eq("product_id", String(productId)).maybeSingle();
    const previousGroups = rowToSpecGroups(existingSpec as JsonObject | null);
    const nextGroups = mergeSpecGroups(previousGroups, nextChanges);
    const payload = specGroupsToRow(nextGroups);
    let specRowId: string | null = (existingSpec as JsonObject | null)?.id ? String((existingSpec as JsonObject).id) : null;
    let inserted = false;

    if (specRowId) {
      const { error: specError } = await db.from("aiq_product_specifications").update(payload).eq("id", specRowId);
      if (specError) return respond({ error: specError.message }, 400);
    } else {
      const { data: insertedRow, error: insertError } = await db.from("aiq_product_specifications").insert({
        organization_id: product.organization_id,
        product_id: product.id,
        version_number: product.version_number,
        ...payload,
      }).select("id").single();
      if (insertError || !insertedRow) return respond({ error: insertError?.message || "Specification insert failed" }, 400);
      specRowId = String(insertedRow.id);
      inserted = true;
    }

    const { data: updatedProduct, error: updateError } = await db.from("aiq_products").update({ updated_by: user.id }).eq("id", String(productId)).eq("version_number", originalVersion).select().single();
    if (updateError || !updatedProduct) {
      if (inserted && specRowId) {
        await db.from("aiq_product_specifications").delete().eq("id", specRowId);
      } else if (specRowId) {
        await db.from("aiq_product_specifications").update(specGroupsToRow(previousGroups)).eq("id", specRowId);
      }
      return respond({
        error: "This product has a newer version. Reload before saving.",
        code: "conflict",
        currentVersion: product.version_number,
        submittedVersion: originalVersion,
        updatedAt: product.updated_at,
        updatedBy: product.updated_by,
      }, 409);
    }

    await audit(
      db,
      updatedProduct as JsonObject,
      "product_specifications_updated",
      { product: product, specifications: previousGroups },
      { product: updatedProduct, specifications: nextGroups, changes: nextChanges },
      `specifications (${resolvedTemplate}): ${reason || Object.keys(nextChanges).map(group => `${group}:${Object.keys(nextChanges[group] as JsonObject).join(",")}`).join("; ")}`,
      user.id,
    );
    return respond({
      data: updatedProduct,
      version_number: updatedProduct.version_number,
      section: "specifications",
    });
  }

  if (["create_product_relationship", "update_product_relationship", "archive_product_relationship", "restore_product_relationship"].includes(String(body.action))) {
    const { productId, originalVersion, relationshipId, targetProductId, changes, reason, section } = body as JsonObject;
    if (!productId || !Number.isInteger(originalVersion)) return respond({ error: "productId and originalVersion are required" }, 400);
    if (section && section !== "relationships") return respond({ error: "Invalid section for relationship mutation", code: "validation_failed" }, 400);

    const sourceResult = await loadProductForMutation(db, String(productId));
    if ("status" in sourceResult) return respond({ error: sourceResult.error }, sourceResult.status);
    const sourceProduct = sourceResult.product as JsonObject;
    if (Number(sourceProduct.version_number) !== Number(originalVersion)) {
      return respond({
        error: "This product has a newer version. Reload before saving.",
        code: "conflict",
        currentVersion: sourceProduct.version_number,
        submittedVersion: originalVersion,
        updatedAt: sourceProduct.updated_at,
        updatedBy: sourceProduct.updated_by,
      }, 409);
    }

    const touchAndAudit = async (actionName: string, oldRecord: unknown, newRecord: unknown, entityId: string | null, rollback: (() => Promise<void>) | null = null) => {
      const touched = await touchProductForVersion(db, String(productId), Number(originalVersion), user.id);
      if ("error" in touched) return respond({ error: touched.error }, touched.status);
      if ("conflict" in touched) {
        if (rollback) await rollback();
        return respond({
          error: "This product has a newer version. Reload before saving.",
          code: "conflict",
          currentVersion: sourceProduct.version_number,
          submittedVersion: originalVersion,
          updatedAt: sourceProduct.updated_at,
          updatedBy: sourceProduct.updated_by,
        }, 409);
      }
      await audit(db, sourceProduct, actionName, oldRecord, newRecord, reason ? String(reason) : undefined, user.id, "aiq_product_relationships", entityId);
      return respond({ data: touched.updated, version_number: touched.updated.version_number });
    };

    if (String(body.action) === "create_product_relationship") {
      const normalizedChanges = isRecord(changes) ? changes : {};
      const targetId = normalizeText(targetProductId);
      if (!targetId) return respond({ error: "targetProductId is required", code: "validation_failed" }, 400);
      const { data: targetProduct, error: targetError } = await db.from("aiq_products").select("*").eq("id", targetId).maybeSingle();
      if (targetError || !targetProduct) return respond({ error: "Target product not found" }, 404);
      const validation = validateRelationshipChanges(normalizedChanges, normalizedChanges.relationship_type, String(sourceProduct.id));
      if (Object.keys(validation.errors).length) return respond({ error: "validation_failed", code: "validation_failed", fieldErrors: validation.errors }, 400);
      const finalType = validation.normalizedType;
      const finalDirection = validation.direction || (BIDIRECTIONAL_RELATIONSHIP_TYPES.has(finalType) ? "bidirectional" : "forward");
      const requiredLevel = RELATIONSHIP_REQUIREMENT_LEVELS.has(String(normalizedChanges.requirement_level || "").trim().toLowerCase())
        ? String(normalizedChanges.requirement_level).trim().toLowerCase()
        : finalType === "required_accessory"
          ? "required"
          : "optional";
      const sourceConfidence = normalizedChanges.source_confidence == null || normalizedChanges.source_confidence === ""
        ? null
        : Number(normalizedChanges.source_confidence);
      const quantity = normalizedChanges.quantity == null || normalizedChanges.quantity === "" ? (finalType === "required_accessory" ? 1 : null) : Number(normalizedChanges.quantity);
      const minimumQuantity = normalizedChanges.minimum_quantity == null || normalizedChanges.minimum_quantity === "" ? null : Number(normalizedChanges.minimum_quantity);
      const maximumQuantity = normalizedChanges.maximum_quantity == null || normalizedChanges.maximum_quantity === "" ? null : Number(normalizedChanges.maximum_quantity);
      const sourceId = String(sourceProduct.id);
      const relatedId = String(targetProduct.id);
      if (sourceId === relatedId) return respond({ error: "A product cannot be related to itself.", code: "validation_failed", fieldErrors: { targetProductId: { code: "self_reference", message: "Select a different product." } } }, 400);
      const { data: activeRelationships } = await db.from("aiq_product_relationships").select("id,product_id,related_product_id").eq("organization_id", sourceProduct.organization_id).eq("relationship_type", finalType).eq("direction", finalDirection).is("archived_at", null);
      const duplicateExists = (activeRelationships || []).some((row: JsonObject) => {
        const forward = String(row.product_id) === sourceId && String(row.related_product_id) === relatedId;
        const reverse = BIDIRECTIONAL_RELATIONSHIP_TYPES.has(finalType) && String(row.product_id) === relatedId && String(row.related_product_id) === sourceId;
        return forward || reverse;
      });
      if (duplicateExists) return respond({ error: "A matching active relationship already exists.", code: "duplicate_relationship" }, 409);
      const row = {
        organization_id: sourceProduct.organization_id,
        product_id: sourceId,
        related_product_id: relatedId,
        relationship_type: finalType,
        relationship_label: relationshipLabel(finalType),
        direction: finalDirection,
        requirement_level: requiredLevel,
        compatibility_status: String(normalizedChanges.compatibility_status || "unverified").trim().toLowerCase(),
        compatibility_notes: normalizeText(normalizedChanges.compatibility_notes || normalizedChanges.notes) || null,
        installation_notes: normalizeText(normalizedChanges.installation_notes) || null,
        quantity,
        minimum_quantity: minimumQuantity,
        maximum_quantity: maximumQuantity,
        same_brand_requirement: Boolean(normalizedChanges.same_brand_requirement),
        compatible_finish_requirement: Boolean(normalizedChanges.compatible_finish_requirement),
        source_type: normalizeText(normalizedChanges.source_type) || "internal",
        source_reference: normalizeText(normalizedChanges.source_reference) || null,
        source_confidence: sourceConfidence,
        effective_start_date: normalizeText(normalizedChanges.effective_start_date) || null,
        effective_end_date: normalizeText(normalizedChanges.effective_end_date) || null,
        archived_at: null,
        archived_by: null,
        created_by: user.id,
        updated_by: user.id,
      };
      const { data: inserted, error: insertError } = await db.from("aiq_product_relationships").insert(row).select("*").single();
      if (insertError || !inserted) return respond({ error: insertError?.message || "Relationship insert failed" }, 400);
      const rollback = async () => { await db.from("aiq_product_relationships").delete().eq("id", String(inserted.id)); };
      return touchAndAudit("product_relationship_created", null, inserted, String(inserted.id), rollback);
    }

    if (!relationshipId) return respond({ error: "relationshipId is required" }, 400);
    const { data: relationship, error: relationshipError } = await db.from("aiq_product_relationships").select("*").eq("id", String(relationshipId)).maybeSingle();
    if (relationshipError || !relationship) return respond({ error: "Relationship not found" }, 404);
    if (String(relationship.product_id) !== String(sourceProduct.id)) return respond({ error: "Relationship not found" }, 404);
    const { data: targetProduct, error: targetError } = await db.from("aiq_products").select("*").eq("id", String(relationship.related_product_id)).maybeSingle();
    if (targetError || !targetProduct) return respond({ error: "Target product not found" }, 404);

    const oldRecord = cloneRecord(relationship);
    const nextRecord: JsonObject = cloneRecord(relationship);
    const normalizedChanges = isRecord(changes) ? changes : {};

    if (String(body.action) === "archive_product_relationship") {
      if (nextRecord.archived_at) return respond({ error: "No changes supplied", code: "no_changes" }, 400);
      nextRecord.archived_at = new Date().toISOString();
      nextRecord.archived_by = user.id;
    } else if (String(body.action) === "restore_product_relationship") {
      if (!nextRecord.archived_at) return respond({ error: "No changes supplied", code: "no_changes" }, 400);
      nextRecord.archived_at = null;
      nextRecord.archived_by = null;
    } else {
      const proposedType = normalizeRelationshipKey(normalizedChanges.relationship_type || relationship.relationship_type);
      const validation = validateRelationshipChanges({ ...normalizedChanges, relationship_type: proposedType }, proposedType, String(sourceProduct.id));
      if (Object.keys(validation.errors).length) return respond({ error: "validation_failed", code: "validation_failed", fieldErrors: validation.errors }, 400);
      if (normalizedChanges.targetProductId && String(normalizedChanges.targetProductId) !== String(relationship.related_product_id)) {
        return respond({ error: "Changing the target product requires creating a new relationship.", code: "validation_failed", fieldErrors: { targetProductId: { code: "immutable", message: "Create a new relationship to change the target product." } } }, 400);
      }
      nextRecord.relationship_type = proposedType;
      nextRecord.relationship_label = relationshipLabel(proposedType);
      nextRecord.direction = validation.direction || nextRecord.direction || "forward";
      nextRecord.requirement_level = RELATIONSHIP_REQUIREMENT_LEVELS.has(String(normalizedChanges.requirement_level || "").trim().toLowerCase())
        ? String(normalizedChanges.requirement_level).trim().toLowerCase()
        : nextRecord.requirement_level;
      nextRecord.compatibility_status = String(normalizedChanges.compatibility_status || nextRecord.compatibility_status || "unverified").trim().toLowerCase();
      nextRecord.compatibility_notes = normalizeText(normalizedChanges.compatibility_notes || normalizedChanges.notes) || nextRecord.compatibility_notes || null;
      nextRecord.installation_notes = normalizeText(normalizedChanges.installation_notes) || nextRecord.installation_notes || null;
      if ("quantity" in normalizedChanges) nextRecord.quantity = normalizedChanges.quantity === "" || normalizedChanges.quantity == null ? null : Number(normalizedChanges.quantity);
      if ("minimum_quantity" in normalizedChanges) nextRecord.minimum_quantity = normalizedChanges.minimum_quantity === "" || normalizedChanges.minimum_quantity == null ? null : Number(normalizedChanges.minimum_quantity);
      if ("maximum_quantity" in normalizedChanges) nextRecord.maximum_quantity = normalizedChanges.maximum_quantity === "" || normalizedChanges.maximum_quantity == null ? null : Number(normalizedChanges.maximum_quantity);
      if ("same_brand_requirement" in normalizedChanges) nextRecord.same_brand_requirement = Boolean(normalizedChanges.same_brand_requirement);
      if ("compatible_finish_requirement" in normalizedChanges) nextRecord.compatible_finish_requirement = Boolean(normalizedChanges.compatible_finish_requirement);
      if ("source_type" in normalizedChanges) nextRecord.source_type = normalizeText(normalizedChanges.source_type) || nextRecord.source_type || "internal";
      if ("source_reference" in normalizedChanges) nextRecord.source_reference = normalizeText(normalizedChanges.source_reference) || null;
      if ("source_confidence" in normalizedChanges) nextRecord.source_confidence = normalizedChanges.source_confidence === "" || normalizedChanges.source_confidence == null ? null : Number(normalizedChanges.source_confidence);
      if ("effective_start_date" in normalizedChanges) nextRecord.effective_start_date = normalizeText(normalizedChanges.effective_start_date) || null;
      if ("effective_end_date" in normalizedChanges) nextRecord.effective_end_date = normalizeText(normalizedChanges.effective_end_date) || null;
    }

    const patch: JsonObject = {};
    for (const key of Object.keys(nextRecord)) {
      if (!Object.is((oldRecord as JsonObject)[key], nextRecord[key])) patch[key] = nextRecord[key];
    }
    if (!Object.keys(patch).length) return respond({ error: "No changes supplied", code: "no_changes" }, 400);

    const { data: activeRelationships } = await db.from("aiq_product_relationships").select("id,product_id,related_product_id").eq("organization_id", sourceProduct.organization_id).eq("relationship_type", String(nextRecord.relationship_type)).eq("direction", String(nextRecord.direction)).is("archived_at", null).neq("id", String(relationship.id));
    const duplicateExists = (activeRelationships || []).some((row: JsonObject) => {
      const forward = String(row.product_id) === String(nextRecord.product_id) && String(row.related_product_id) === String(nextRecord.related_product_id);
      const reverse = BIDIRECTIONAL_RELATIONSHIP_TYPES.has(String(nextRecord.relationship_type)) && String(row.product_id) === String(nextRecord.related_product_id) && String(row.related_product_id) === String(nextRecord.product_id);
      return forward || reverse;
    });
    if (duplicateExists) return respond({ error: "A matching active relationship already exists.", code: "duplicate_relationship" }, 409);

    const { error: updateError } = await db.from("aiq_product_relationships").update({ ...patch, updated_by: user.id }).eq("id", String(relationshipId));
    if (updateError) return respond({ error: updateError.message }, 400);
    const rollback = async () => { await db.from("aiq_product_relationships").update(oldRecord as JsonObject).eq("id", String(relationshipId)); };
    const actionName = String(body.action) === "archive_product_relationship" ? "product_relationship_archived" : String(body.action) === "restore_product_relationship" ? "product_relationship_restored" : "product_relationship_updated";
    return touchAndAudit(actionName, oldRecord, nextRecord, String(relationshipId), rollback);
  }

  if (["update_document_metadata", "archive_document", "restore_document", "update_image_metadata", "set_primary_image", "reorder_images", "archive_image", "restore_image"].includes(String(body.action))) {
    const { productId, originalVersion, documentId, assetId, changes, orderedAssetIds, reason, section } = body as JsonObject;
    if (!productId || !Number.isInteger(originalVersion)) return respond({ error: "productId and originalVersion are required" }, 400);
    if (section && !["documents", "assets"].includes(String(section))) return respond({ error: "Invalid section for document or image mutation", code: "validation_failed" }, 400);
    const productResult = await loadProductForMutation(db, String(productId));
    if ("status" in productResult) return respond({ error: productResult.error }, productResult.status);
    const product = productResult.product as JsonObject;
    if (Number(product.version_number) !== Number(originalVersion)) {
      return respond({
        error: "This product has a newer version. Reload before saving.",
        code: "conflict",
        currentVersion: product.version_number,
        submittedVersion: originalVersion,
        updatedAt: product.updated_at,
        updatedBy: product.updated_by,
      }, 409);
    }

    const updateProductTouch = async (entityAction: string, oldRecord: unknown, newRecord: unknown, entityType: string, entityId: string | null, rollback: (() => Promise<void>) | null = null) => {
      const touched = await touchProductForVersion(db, String(productId), Number(originalVersion), user.id);
      if ("error" in touched) return respond({ error: touched.error }, touched.status);
      if ("conflict" in touched) {
        if (rollback) await rollback();
        return respond({
          error: "This product has a newer version. Reload before saving.",
          code: "conflict",
          currentVersion: product.version_number,
          submittedVersion: originalVersion,
          updatedAt: product.updated_at,
          updatedBy: product.updated_by,
        }, 409);
      }
      await audit(db, product, entityAction, oldRecord, newRecord, reason ? String(reason) : undefined, user.id, entityType, entityId);
      return respond({ data: touched.updated, version_number: touched.updated.version_number });
    };

    if (String(body.action) === "update_document_metadata" || String(body.action) === "archive_document" || String(body.action) === "restore_document") {
      if (!documentId) return respond({ error: "documentId is required" }, 400);
      const { data: document, error: docError } = await db.from("aiq_documents").select("*").eq("id", String(documentId)).maybeSingle();
      if (docError || !document || String(document.product_id) !== String(product.id)) return respond({ error: "Document not found" }, 404);
      const normalizedChanges = isRecord(changes) ? changes : {};
      const { errors, type } = validateDocChanges(normalizedChanges);
      if (Object.keys(errors).length) return respond({ error: "validation_failed", code: "validation_failed", fieldErrors: errors }, 400);
      const oldRecord = cloneRecord(document);
      const nextRecord: JsonObject = cloneRecord(document);
      if (String(body.action) === "archive_document") {
        nextRecord.archived_at = new Date().toISOString();
        nextRecord.archived_by = user.id;
      } else if (String(body.action) === "restore_document") {
        nextRecord.archived_at = null;
        nextRecord.archived_by = null;
      } else {
        nextRecord.title = normalizeText(normalizedChanges.title);
        nextRecord.document_type = type || document.document_type;
        nextRecord.language = normalizeText(normalizedChanges.language) || null;
        nextRecord.version = normalizeText(normalizedChanges.version) || null;
        nextRecord.source_type = normalizeText(normalizedChanges.source_type) || null;
        nextRecord.source_reference = normalizeText(normalizedChanges.source_reference) || null;
        nextRecord.description = normalizeText(normalizedChanges.description) || null;
        nextRecord.public_visible = !!normalizedChanges.public_visible;
        nextRecord.approval_status = normalizeText(normalizedChanges.approval_status) || "draft";
      }
      const patch: JsonObject = {};
      for (const key of Object.keys(nextRecord)) {
        if (!Object.is((oldRecord as JsonObject)[key], nextRecord[key])) patch[key] = nextRecord[key];
      }
      if (!Object.keys(patch).length) return respond({ error: "No changes supplied", code: "no_changes" }, 400);
      const { error: updateError } = await db.from("aiq_documents").update(patch).eq("id", String(documentId));
      if (updateError) return respond({ error: updateError.message }, 400);
      const rolledBack = async () => { await db.from("aiq_documents").update(oldRecord as JsonObject).eq("id", String(documentId)); };
      const actionName = String(body.action) === "archive_document" ? "document_archived" : String(body.action) === "restore_document" ? "document_restored" : "document_metadata_updated";
      return updateProductTouch(actionName, { document: oldRecord }, { document: nextRecord }, "aiq_documents", String(documentId), rolledBack);
    }

    if (String(body.action) === "update_image_metadata" || String(body.action) === "set_primary_image" || String(body.action) === "archive_image" || String(body.action) === "restore_image" || String(body.action) === "reorder_images") {
      if (String(body.action) === "reorder_images") {
        if (!Array.isArray(orderedAssetIds) || !orderedAssetIds.length) return respond({ error: "orderedAssetIds are required" }, 400);
        const { data: assets, error: assetError } = await db.from("mfr_assets").select("*").eq("product_id", String(product.id)).is("archived_at", null).order("display_order", { ascending: true }).order("updated_at", { ascending: false });
        if (assetError) return respond({ error: assetError.message }, 400);
        const active = (assets || []).filter((row: JsonObject) => !row.archived_at);
        const activeIds = active.map((row: JsonObject) => String(row.id));
        const requested = [...new Set((orderedAssetIds as unknown[]).map(v => String(v)))];
        if (requested.length !== activeIds.length || requested.some(id => !activeIds.includes(id))) {
          return respond({ error: "Reorder requests must include exactly the active images for this product.", code: "validation_failed" }, 400);
        }
        const oldRows = cloneRecord(active);
        for (let i = 0; i < requested.length; i++) {
          const asset = active.find((row: JsonObject) => String(row.id) === requested[i]);
          if (!asset) continue;
          const { error: rowError } = await db.from("mfr_assets").update({ display_order: i + 1 }).eq("id", String(asset.id));
          if (rowError) return respond({ error: rowError.message }, 400);
        }
        const rollback = async () => {
          for (const row of oldRows as JsonObject[]) await db.from("mfr_assets").update({ display_order: row.display_order }).eq("id", String(row.id));
        };
        const touched = await touchProductForVersion(db, String(productId), Number(originalVersion), user.id);
        if ("error" in touched) return respond({ error: touched.error }, touched.status);
        if ("conflict" in touched) {
          await rollback();
          return respond({
            error: "This product has a newer version. Reload before saving.",
            code: "conflict",
            currentVersion: product.version_number,
            submittedVersion: originalVersion,
            updatedAt: product.updated_at,
            updatedBy: product.updated_by,
          }, 409);
        }
        await audit(db, product, "images_reordered", { assets: oldRows }, { orderedAssetIds: requested }, reason ? String(reason) : undefined, user.id, "mfr_assets", null);
        return respond({ data: touched.updated, version_number: touched.updated.version_number });
      }

      if (!assetId) return respond({ error: "assetId is required" }, 400);
      const { data: asset, error: assetError } = await db.from("mfr_assets").select("*").eq("id", String(assetId)).maybeSingle();
      if (assetError || !asset || String(asset.product_id) !== String(product.id)) return respond({ error: "Image not found" }, 404);
      const normalizedChanges = isRecord(changes) ? changes : {};
      const { errors, type } = validateImageChanges(normalizedChanges);
      if (Object.keys(errors).length) return respond({ error: "validation_failed", code: "validation_failed", fieldErrors: errors }, 400);
      const oldRecord = cloneRecord(asset);
      const nextRecord: JsonObject = cloneRecord(asset);
      let primarySnapshot: JsonObject[] = [];

      if (String(body.action) === "archive_image") {
        nextRecord.archived_at = new Date().toISOString();
        nextRecord.archived_by = user.id;
        nextRecord.is_primary = false;
      } else if (String(body.action) === "restore_image") {
        nextRecord.archived_at = null;
        nextRecord.archived_by = null;
      } else {
        nextRecord.title = normalizeText(normalizedChanges.title);
        nextRecord.image_type = type || asset.image_type;
        nextRecord.alt_text = normalizeText(normalizedChanges.alt_text) || null;
        nextRecord.display_order = normalizedChanges.display_order === "" || normalizedChanges.display_order == null ? null : Number(normalizedChanges.display_order);
        nextRecord.source_type = normalizeText(normalizedChanges.source_type) || null;
        nextRecord.source_reference = normalizeText(normalizedChanges.source_reference) || null;
        if ("is_published" in normalizedChanges) nextRecord.is_published = !!normalizedChanges.is_published;
        if ("is_primary" in normalizedChanges) nextRecord.is_primary = !!normalizedChanges.is_primary;
      }
      if (String(body.action) === "set_primary_image") nextRecord.is_primary = true;
      if (nextRecord.archived_at && nextRecord.is_primary) nextRecord.is_primary = false;
      if (nextRecord.is_primary) {
        const { data: primaries } = await db.from("mfr_assets").select("id").eq("product_id", String(product.id)).eq("is_primary", true).is("archived_at", null);
        primarySnapshot = cloneRecord(primaries || []);
        for (const row of primarySnapshot as JsonObject[]) {
          if (String(row.id) !== String(asset.id)) {
            const { error: clearError } = await db.from("mfr_assets").update({ is_primary: false }).eq("id", String(row.id));
            if (clearError) return respond({ error: clearError.message }, 400);
          }
        }
      }
      const patch: JsonObject = {};
      for (const key of Object.keys(nextRecord)) {
        if (!Object.is((oldRecord as JsonObject)[key], nextRecord[key])) patch[key] = nextRecord[key];
      }
      if (!Object.keys(patch).length) return respond({ error: "No changes supplied", code: "no_changes" }, 400);
      const { error: updateError } = await db.from("mfr_assets").update(patch).eq("id", String(assetId));
      if (updateError) return respond({ error: updateError.message }, 400);
      const rollback = async () => {
        await db.from("mfr_assets").update(oldRecord as JsonObject).eq("id", String(assetId));
        for (const row of primarySnapshot as JsonObject[]) {
          await db.from("mfr_assets").update({ is_primary: true }).eq("id", String(row.id));
        }
      };
      const primaryChanged = Object.prototype.hasOwnProperty.call(normalizedChanges, "is_primary") && Boolean((oldRecord as JsonObject).is_primary) !== Boolean(nextRecord.is_primary);
      const actionName = String(body.action) === "archive_image" ? "image_archived" : String(body.action) === "restore_image" ? "image_restored" : primaryChanged ? "image_primary_changed" : "image_metadata_updated";
      return updateProductTouch(actionName, { image: oldRecord }, { image: nextRecord }, "mfr_assets", String(assetId), rollback);
    }
  }

  return respond({ error: "Unknown action" }, 400);
});
