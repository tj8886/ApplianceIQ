(() => {
  const slug = value => String(value || "").toLowerCase().trim().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
  const clone = value => JSON.parse(JSON.stringify(value));
  const templateNames = {
    refrigeration: "Refrigeration",
    dishwashers: "Dishwashers",
    cooking: "Cooking",
    laundry: "Laundry",
    ventilation: "Ventilation",
    microwaves: "Microwaves",
    vacuums: "Vacuums",
    outdoor: "Outdoor Appliances",
    small_appliances: "Small Appliances",
    general: "General Appliance",
  };
  const templateAliases = {
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
  const unitAliases = {
    in: ["in", "inch", "inches"],
    cm: ["cm", "centimeter", "centimeters"],
    mm: ["mm", "millimeter", "millimeters"],
    lb: ["lb", "lbs", "pound", "pounds"],
    kg: ["kg", "kilogram", "kilograms"],
    "cu. ft.": ["cu. ft.", "cu ft", "cubic feet", "ft3"],
    L: ["L", "l", "litre", "litres", "liter", "liters"],
    "place settings": ["place settings"],
    bottles: ["bottles"],
    loads: ["loads"],
    V: ["V", "volt", "volts"],
    A: ["A", "amp", "amps", "amperage"],
    W: ["W", "w", "watt", "watts"],
    kW: ["kW", "kw"],
    Hz: ["Hz", "hz"],
    CFM: ["CFM", "cfm"],
    BTU: ["BTU", "btu"],
    dBA: ["dBA", "dba"],
    rpm: ["rpm", "RPM"],
    minutes: ["minutes", "minute", "min"],
    hours: ["hours", "hour", "hrs", "hr"],
    gallons: ["gallons", "gallon", "gal"],
    litres: ["litres", "litres", "liters", "liter"],
    sq_in: ["sq in", "sq_in", "square inches"],
    percent: ["%", "percent", "percentage"],
  };
  const byValue = map => Object.entries(map).reduce((acc, [canonical, aliases]) => {
    aliases.forEach(alias => { acc[String(alias).toLowerCase()] = canonical; });
    acc[String(canonical).toLowerCase()] = canonical;
    return acc;
  }, {});
  const canonicalUnitLookup = byValue(unitAliases);
  const canonicalValue = value => {
    if (value == null || value === "") return value;
    const text = String(value).trim();
    return canonicalUnitLookup[text.toLowerCase()] || text;
  };
  const normalizeUnit = (unit, allowedUnits = []) => {
    if (unit == null || unit === "") return "";
    const canonical = canonicalValue(unit);
    const allowed = allowedUnits.length ? allowedUnits : [canonical];
    const match = allowed.find(candidate => String(candidate).toLowerCase() === String(canonical).toLowerCase());
    return match || canonical;
  };
  const field = (section, key, label, fieldType = "text", unit = "", requiredLevel = "optional", more = {}) => Object.assign({
    section,
    key,
    label,
    fieldType,
    unit,
    allowedUnits: unit ? [unit] : [],
    allowedValues: [],
    requiredLevel,
    minimum: null,
    maximum: null,
    step: fieldType === "number" ? 1 : null,
    displayOrder: 0,
    helpText: "",
    applicability: null,
    validationRules: [],
    editable: true,
    aliases: [],
  }, more);
  const number = (section, key, label, unit = "", requiredLevel = "optional", more = {}) => field(section, key, label, "number", unit, requiredLevel, { minimum: 0, ...more });
  const measurement = (section, key, label, unit = "in", requiredLevel = "optional", more = {}) => field(section, key, label, "measurement", unit, requiredLevel, {
    allowedUnits: more.allowedUnits || [unit, "cm", "mm"],
    minimum: 0,
    step: more.step ?? 0.1,
    ...more,
  });
  const boolean = (section, key, label, requiredLevel = "optional", more = {}) => field(section, key, label, "boolean", "", requiredLevel, more);
  const select = (section, key, label, allowedValues, requiredLevel = "optional", more = {}) => field(section, key, label, "select", "", requiredLevel, {
    allowedValues,
    ...more,
  });
  const multi = (section, key, label, allowedValues = [], requiredLevel = "optional", more = {}) => field(section, key, label, "multi-select", "", requiredLevel, {
    allowedValues,
    ...more,
  });
  const requirement = (section, key, label, requiredLevel = "optional", more = {}) => field(section, key, label, "electrical requirement", "", requiredLevel, more);
  const gasRequirement = (section, key, label, requiredLevel = "optional", more = {}) => field(section, key, label, "gas requirement", "", requiredLevel, more);
  const text = (section, key, label, requiredLevel = "optional", more = {}) => field(section, key, label, "text", "", requiredLevel, more);
  const sectionDef = (name, fields) => ({ name, fields: fields.map((item, index) => ({ ...item, displayOrder: item.displayOrder || index + 1 })) });
  const template = (match, sections) => {
    const flat = sections.flatMap(section => section.fields);
    return {
      match,
      sections,
      fields: flat,
      fieldMap: flat.reduce((acc, entry) => {
        acc[entry.key] = entry;
        return acc;
      }, {}),
    };
  };
  const templates = {
    refrigeration: template(templateAliases.refrigeration, [
      sectionDef("Identity and configuration", [
        select("configuration", "refrigerator_type", "Refrigerator type", ["French door", "Side-by-side", "Top freezer", "Bottom freezer", "Column", "Compact"], "required"),
        select("configuration", "configuration", "Configuration", ["Freestanding", "Built-in", "Counter-depth", "Column", "Panel-ready"], "optional"),
        select("configuration", "installation_type", "Installation type", ["Freestanding", "Built-in", "Integrated", "Counter-depth"], "optional"),
        boolean("configuration", "counter_depth", "Counter-depth status"),
        boolean("configuration", "panel_ready", "Panel-ready status"),
        select("configuration", "door_hinge", "Door hinge", ["Left", "Right", "Reversible", "French split"], "optional"),
        select("configuration", "door_swing", "Door swing", ["Left", "Right", "Reversible", "French split"], "optional"),
        number("configuration", "number_of_doors", "Number of doors", "", "optional", { minimum: 1, step: 1 }),
      ]),
      sectionDef("Capacity", [
        number("performance", "total_capacity", "Total capacity", "cu. ft.", "required", { allowedUnits: ["cu. ft.", "L"] }),
        number("performance", "refrigerator_capacity", "Refrigerator capacity", "cu. ft.", "optional", { allowedUnits: ["cu. ft.", "L"] }),
        number("performance", "freezer_capacity", "Freezer capacity", "cu. ft.", "optional", { allowedUnits: ["cu. ft.", "L"] }),
      ]),
      sectionDef("Dimensions", [
        measurement("dimensions", "width", "Overall width", "in", "required"),
        measurement("dimensions", "height", "Overall height", "in", "required"),
        measurement("dimensions", "depth", "Overall depth", "in", "required"),
        measurement("dimensions", "depth_without_handles", "Depth without handles", "in"),
        measurement("dimensions", "depth_without_doors", "Depth without doors", "in"),
        measurement("dimensions", "depth_with_door_open", "Depth with door open", "in"),
        measurement("installation", "cutout_width", "Cutout width", "in"),
        measurement("installation", "cutout_height", "Cutout height", "in"),
        measurement("installation", "cutout_depth", "Cutout depth", "in"),
        measurement("installation", "installation_depth", "Installation depth", "in"),
        measurement("installation", "minimum_clearance", "Minimum clearance", "in"),
        number("dimensions", "weight", "Weight", "lb"),
      ]),
      sectionDef("Features", [
        boolean("performance", "ice_maker", "Ice maker"),
        boolean("performance", "water_dispenser", "Water dispenser"),
        boolean("performance", "water_connection_required", "Water connection required"),
        boolean("performance", "water_filtration", "Water filtration"),
        boolean("performance", "dual_evaporator", "Dual evaporator"),
        boolean("performance", "temperature_zones", "Temperature zones"),
        boolean("performance", "door_alarm", "Door alarm"),
        boolean("performance", "sabbath_mode", "Sabbath mode"),
        boolean("performance", "wifi", "Wi-Fi"),
        boolean("certifications", "energy_star", "ENERGY STAR"),
        text("performance", "annual_energy_consumption", "Annual energy consumption", "optional", { unit: "kWh" }),
        text("notes", "additional_notes", "Additional notes"),
      ]),
      sectionDef("Electrical", [
        requirement("electrical", "electrical_requirements", "Electrical requirements"),
        number("electrical", "voltage", "Electrical voltage", "V", "required", { allowedUnits: ["V", "Hz"], minimum: 0 }),
        number("electrical", "amperage", "Amperage", "A", "optional", { allowedUnits: ["A"], minimum: 0 }),
        number("electrical", "frequency", "Frequency", "Hz", "optional", { allowedUnits: ["Hz"], minimum: 0 }),
        boolean("electrical", "dedicated_circuit_required", "Dedicated circuit requirement"),
      ]),
    ]),
    dishwashers: template(templateAliases.dishwashers, [
      sectionDef("Identity and configuration", [
        select("configuration", "dishwasher_type", "Dishwasher type", ["Built-in", "Portable", "Drawer", "Countertop"], "required"),
        select("configuration", "installation_type", "Installation type", ["Built-in", "Portable", "Countertop"], "optional"),
        boolean("configuration", "panel_ready", "Panel-ready status"),
        text("configuration", "handle_type", "Handle type"),
      ]),
      sectionDef("Dimensions", [
        measurement("dimensions", "width", "Width", "in", "required"),
        measurement("dimensions", "height", "Height", "in"),
        measurement("dimensions", "depth", "Depth", "in"),
        measurement("installation", "adjustable_height_range", "Adjustable height range", "in"),
        measurement("installation", "cutout_width", "Cutout width", "in"),
        measurement("installation", "cutout_height", "Cutout height", "in"),
        measurement("installation", "cutout_depth", "Cutout depth", "in"),
        number("dimensions", "weight", "Weight", "lb"),
      ]),
      sectionDef("Performance", [
        number("performance", "place_settings", "Place-setting capacity", "place settings", "required", { allowedUnits: ["place settings"] }),
        number("performance", "noise_level", "Sound level", "dBA", "recommended", { allowedUnits: ["dBA"], minimum: 0, maximum: 100 }),
        number("performance", "rack_count", "Number of racks", "", "optional", { minimum: 0, step: 1 }),
        boolean("performance", "third_rack", "Third rack"),
        boolean("performance", "adjustable_rack", "Adjustable rack"),
        text("performance", "tub_material", "Tub material"),
        text("performance", "drying_system", "Drying system"),
        multi("performance", "wash_cycles", "Wash cycles", []),
        text("performance", "filtration_system", "Filtration system"),
        boolean("performance", "hard_food_disposer", "Hard-food disposer"),
        boolean("performance", "leak_protection", "Leak protection"),
        boolean("performance", "wifi", "Wi-Fi"),
        boolean("certifications", "energy_star", "ENERGY STAR"),
      ]),
      sectionDef("Installation and utility", [
        requirement("electrical", "electrical_requirements", "Electrical requirements"),
        text("installation", "water_connection", "Water connection"),
        text("installation", "drain_requirements", "Drain requirements"),
      ]),
    ]),
    cooking: template(templateAliases.cooking, [
      sectionDef("Identity and configuration", [
        select("configuration", "product_type", "Product type", ["Range", "Cooktop", "Rangetop", "Wall oven", "Speed oven", "Warming drawer", "Combination oven"], "required"),
        select("configuration", "fuel_type", "Fuel type", ["Gas", "Electric", "Dual fuel", "Induction"], "required"),
        select("configuration", "cooktop_fuel_type", "Cooktop fuel type", ["Gas", "Electric", "Induction", "Dual fuel"], "optional"),
        select("configuration", "oven_fuel_type", "Oven fuel type", ["Gas", "Electric", "Dual fuel"], "optional"),
        boolean("configuration", "double_oven", "Double oven"),
        boolean("performance", "convection", "Convection"),
        boolean("performance", "induction", "Induction"),
        boolean("performance", "air_fry", "Air fry"),
        boolean("performance", "self_clean", "Self-cleaning"),
        boolean("performance", "steam_clean", "Steam clean"),
        boolean("performance", "warming_drawer", "Warming drawer"),
        boolean("performance", "griddle", "Griddle"),
        boolean("performance", "wifi", "Wi-Fi features"),
        boolean("performance", "sabbath_mode", "Sabbath mode"),
      ]),
      sectionDef("Dimensions", [
        measurement("dimensions", "width", "Width", "in", "required"),
        measurement("dimensions", "height", "Height", "in"),
        measurement("dimensions", "depth", "Depth", "in"),
        measurement("installation", "cutout_width", "Cutout width", "in"),
        measurement("installation", "cutout_height", "Cutout height", "in"),
        measurement("installation", "cutout_depth", "Cutout depth", "in"),
        measurement("installation", "minimum_clearances", "Minimum clearances", "in"),
        number("dimensions", "weight", "Weight", "lb"),
      ]),
      sectionDef("Performance", [
        number("performance", "capacity", "Capacity", "cu. ft.", "optional", { allowedUnits: ["cu. ft.", "L"] }),
        number("performance", "burner_count", "Burner count", "", "optional", { minimum: 0, step: 1 }),
        number("performance", "element_count", "Element count", "", "optional", { minimum: 0, step: 1 }),
        number("performance", "oven_count", "Oven count", "", "optional", { minimum: 0, step: 1 }),
        text("performance", "convection_type", "Convection type"),
        text("performance", "burner_output", "Burner output"),
      ]),
      sectionDef("Electrical and gas", [
        requirement("electrical", "electrical_requirements", "Electrical requirements"),
        number("electrical", "voltage", "Electrical voltage", "V", "optional", { allowedUnits: ["V"], minimum: 0 }),
        number("electrical", "amperage", "Electrical amperage", "A", "optional", { allowedUnits: ["A"], minimum: 0 }),
        text("electrical", "required_breaker", "Required breaker"),
        gasRequirement("gas", "gas_requirements", "Gas requirements"),
      ]),
    ]),
    laundry: template(templateAliases.laundry, [
      sectionDef("Identity and configuration", [
        select("configuration", "product_type", "Product type", ["Washer", "Dryer", "Washer dryer combo"], "required"),
        select("configuration", "load_style", "Load style", ["Front load", "Top load", "Side load", "Stackable"], "optional"),
        select("configuration", "vent_type", "Vented or ventless", ["Vented", "Ventless"], "optional"),
        boolean("configuration", "heat_pump", "Heat pump"),
        boolean("configuration", "stackable", "Stackable"),
        boolean("configuration", "pedestal_compatible", "Pedestal compatible"),
        boolean("configuration", "reversible_door", "Reversible door"),
      ]),
      sectionDef("Dimensions", [
        measurement("dimensions", "width", "Width", "in", "required"),
        measurement("dimensions", "height", "Height", "in"),
        measurement("dimensions", "depth", "Depth", "in"),
        measurement("dimensions", "depth_with_door_open", "Depth with door open", "in"),
        number("dimensions", "weight", "Weight", "lb"),
      ]),
      sectionDef("Performance", [
        number("performance", "capacity", "Capacity", "cu. ft.", "required", { allowedUnits: ["cu. ft.", "L", "loads"] }),
        multi("performance", "wash_cycles", "Wash cycles", []),
        multi("performance", "dry_cycles", "Dry cycles", []),
        boolean("performance", "steam", "Steam"),
        boolean("performance", "automatic_dispensing", "Automatic dispensing"),
        boolean("performance", "wifi", "Wi-Fi"),
        boolean("certifications", "energy_star", "ENERGY STAR"),
        number("performance", "spin_speed", "Spin speed", "rpm", "optional", { allowedUnits: ["rpm"], minimum: 0 }),
      ]),
      sectionDef("Electrical and utility", [
        requirement("electrical", "electrical_requirements", "Electrical requirements"),
        number("electrical", "voltage", "Electrical voltage", "V", "optional", { allowedUnits: ["V"], minimum: 0 }),
        number("electrical", "amperage", "Electrical amperage", "A", "optional", { allowedUnits: ["A"], minimum: 0 }),
        gasRequirement("gas", "gas_requirements", "Gas requirements"),
        text("installation", "water_requirements", "Water requirements"),
        text("installation", "drain_requirements", "Drain requirements"),
      ]),
      sectionDef("Accessories", [
        text("installation", "compatible_stacking_kit", "Compatible stacking kit"),
        boolean("installation", "washer_hoses_included", "Washer hoses included"),
        boolean("installation", "power_cord_included", "Power cord included"),
        boolean("installation", "dryer_vent_included", "Dryer vent included"),
      ]),
    ]),
    ventilation: template(templateAliases.ventilation, [
      sectionDef("Identity and configuration", [
        select("configuration", "hood_type", "Hood type", ["Under-cabinet", "Wall mount", "Island", "Insert", "Downdraft"], "required"),
        select("configuration", "installation_type", "Installation type", ["Wall mount", "Under-cabinet", "Island", "Downdraft", "Insert"], "optional"),
        select("ventilation", "duct_direction", "Duct direction", ["Vertical", "Horizontal", "Convertible"], "optional"),
        boolean("ventilation", "ducted_or_recirculating", "Ducted or recirculating"),
        boolean("ventilation", "recirculation_kit", "Recirculation kit"),
        boolean("ventilation", "blower_included", "Blower included"),
        select("ventilation", "blower_type", "Blower type", ["Internal", "External", "Inline"], "optional"),
      ]),
      sectionDef("Dimensions", [
        measurement("dimensions", "width", "Width", "in", "required"),
        measurement("dimensions", "height", "Height", "in"),
        measurement("dimensions", "depth", "Depth", "in"),
        number("dimensions", "weight", "Weight", "lb"),
      ]),
      sectionDef("Performance", [
        number("ventilation", "maximum_cfm", "Maximum CFM", "CFM", "required", { allowedUnits: ["CFM"], minimum: 0 }),
        number("ventilation", "minimum_cfm", "Minimum CFM", "CFM", "optional", { allowedUnits: ["CFM"], minimum: 0 }),
        number("performance", "speed_count", "Speed count", "", "optional", { minimum: 0, step: 1 }),
        number("performance", "noise_level", "Noise level", "dBA", "optional", { allowedUnits: ["dBA"], minimum: 0 }),
        text("ventilation", "filter_type", "Filter type"),
        boolean("performance", "lighting", "Lighting"),
        boolean("performance", "smart_connectivity", "Smart connectivity"),
      ]),
      sectionDef("Installation", [
        text("ventilation", "duct_size", "Duct size"),
        boolean("ventilation", "make_up_air_consideration", "Make-up air consideration"),
        text("installation", "clearance_above_gas_cooking", "Clearance above gas cooking"),
        text("installation", "clearance_above_electric_cooking", "Clearance above electric cooking"),
        requirement("electrical", "electrical_requirements", "Electrical requirements"),
      ]),
    ]),
    microwaves: template(templateAliases.microwaves, [
      sectionDef("Identity and configuration", [
        select("configuration", "microwave_type", "Microwave type", ["Countertop", "Over-the-range", "Built-in", "Drawer"], "required"),
        select("configuration", "installation_type", "Installation type", ["Countertop", "Over-the-range", "Built-in", "Drawer"], "optional"),
        boolean("configuration", "trim_kit_compatibility", "Trim-kit compatibility"),
        boolean("configuration", "built_in_kit_required", "Built-in kit required"),
      ]),
      sectionDef("Dimensions", [
        measurement("dimensions", "width", "Width", "in", "required"),
        measurement("dimensions", "height", "Height", "in"),
        measurement("dimensions", "depth", "Depth", "in"),
        measurement("installation", "cutout_width", "Cutout width", "in"),
        measurement("installation", "cutout_height", "Cutout height", "in"),
        measurement("installation", "cutout_depth", "Cutout depth", "in"),
        number("dimensions", "weight", "Weight", "lb"),
      ]),
      sectionDef("Performance", [
        number("performance", "capacity", "Capacity", "cu. ft.", "required", { allowedUnits: ["cu. ft.", "L"] }),
        number("performance", "power", "Power", "W", "optional", { allowedUnits: ["W", "kW"], minimum: 0 }),
        boolean("performance", "convection", "Convection"),
        boolean("performance", "air_fry", "Air fry"),
        boolean("performance", "sensor_cooking", "Sensor cooking"),
        number("ventilation", "venting_cfm", "Venting CFM", "CFM", "optional", { allowedUnits: ["CFM"], minimum: 0 }),
        number("performance", "turntable_size", "Turntable size", "in", "optional", { allowedUnits: ["in", "cm"], minimum: 0 }),
      ]),
      sectionDef("Electrical", [
        requirement("electrical", "electrical_requirements", "Electrical requirements"),
        number("electrical", "voltage", "Electrical voltage", "V", "optional", { allowedUnits: ["V"], minimum: 0 }),
        number("electrical", "amperage", "Amperage", "A", "optional", { allowedUnits: ["A"], minimum: 0 }),
        text("electrical", "required_breaker", "Required breaker"),
      ]),
    ]),
    vacuums: template(templateAliases.vacuums, [
      sectionDef("Identity and configuration", [
        select("configuration", "vacuum_type", "Vacuum type", ["Upright", "Canister", "Robot", "Stick", "Handheld"], "required"),
        select("configuration", "cleaning_system", "Cleaning system", ["Bagged", "Bagless", "Hybrid"], "optional"),
        boolean("configuration", "corded_or_cordless", "Corded or cordless"),
        boolean("performance", "wet_cleaning", "Wet cleaning"),
        boolean("performance", "mop_function", "Mop function"),
        boolean("performance", "mapping", "Mapping"),
        boolean("performance", "obstacle_avoidance", "Obstacle avoidance"),
        boolean("performance", "auto_empty", "Auto-empty"),
        boolean("performance", "self_cleaning", "Self-cleaning"),
      ]),
      sectionDef("Dimensions", [
        measurement("dimensions", "width", "Width", "in"),
        measurement("dimensions", "height", "Height", "in"),
        measurement("dimensions", "depth", "Depth", "in"),
        number("dimensions", "weight", "Weight", "lb"),
        text("installation", "dock_dimensions", "Dock dimensions"),
      ]),
      sectionDef("Performance", [
        number("performance", "suction_power", "Suction power", "W", "optional", { allowedUnits: ["W", "kW"], minimum: 0 }),
        number("performance", "runtime", "Runtime", "minutes", "optional", { allowedUnits: ["minutes", "hours"], minimum: 0 }),
        number("performance", "charge_time", "Charge time", "minutes", "optional", { allowedUnits: ["minutes", "hours"], minimum: 0 }),
        text("performance", "battery_type", "Battery type"),
        number("performance", "dustbin_capacity", "Dustbin capacity", "L", "optional", { allowedUnits: ["L", "cu. ft."], minimum: 0 }),
        text("performance", "bagged_or_bagless", "Bagged or bagless"),
        text("performance", "filtration", "Filtration"),
        number("performance", "noise_level", "Noise level", "dBA", "optional", { allowedUnits: ["dBA"], minimum: 0 }),
        boolean("performance", "wifi", "Connected features"),
      ]),
    ]),
    outdoor: template(templateAliases.outdoor, [
      sectionDef("Identity and configuration", [
        select("configuration", "product_type", "Product type", ["Grill", "Griddle", "Pizza oven", "Smoker", "Outdoor refrigerator", "Outdoor burner"], "required"),
        select("configuration", "fuel_type", "Fuel type", ["Gas", "Charcoal", "Electric", "Pellet"], "required"),
        select("configuration", "installation_type", "Installation type", ["Built-in", "Freestanding"], "optional"),
        boolean("configuration", "weather_resistance", "Weather resistance"),
        text("configuration", "material", "Material"),
        boolean("configuration", "cover_compatibility", "Cover compatibility"),
      ]),
      sectionDef("Dimensions", [
        measurement("dimensions", "width", "Width", "in", "required"),
        measurement("dimensions", "height", "Height", "in"),
        measurement("dimensions", "depth", "Depth", "in"),
        measurement("installation", "cutout_width", "Cutout width", "in"),
        measurement("installation", "cutout_height", "Cutout height", "in"),
        measurement("installation", "cutout_depth", "Cutout depth", "in"),
        number("dimensions", "weight", "Weight", "lb"),
      ]),
      sectionDef("Performance", [
        number("performance", "cooking_area", "Main grilling area", "sq_in", "optional", { allowedUnits: ["sq_in"], minimum: 0 }),
        number("performance", "total_cooking_area", "Total cooking area", "sq_in", "optional", { allowedUnits: ["sq_in"], minimum: 0 }),
        number("performance", "burner_count", "Burner count", "", "optional", { minimum: 0, step: 1 }),
        number("performance", "total_btu", "Total BTU", "BTU", "optional", { allowedUnits: ["BTU"], minimum: 0 }),
        boolean("performance", "rotisserie", "Rotisserie"),
        boolean("performance", "side_burner", "Side burner"),
      ]),
      sectionDef("Electrical and gas", [
        requirement("electrical", "electrical_requirements", "Electrical requirements"),
        gasRequirement("gas", "gas_requirements", "Gas requirements"),
        text("installation", "minimum_clearances", "Minimum clearances"),
      ]),
    ]),
    small_appliances: template(templateAliases.small_appliances, [
      sectionDef("Identity and configuration", [
        select("configuration", "product_type", "Product type", ["Blender", "Coffee maker", "Mixer", "Toaster", "Processor", "Kettle", "Air fryer", "Other"], "required"),
        number("performance", "capacity", "Capacity", "L", "optional", { allowedUnits: ["L", "cu. ft."], minimum: 0 }),
        number("performance", "speed_settings", "Speed settings", "", "optional", { minimum: 0, step: 1 }),
        text("performance", "temperature_range", "Temperature range"),
        boolean("performance", "dishwasher_safe_parts", "Dishwasher-safe parts"),
        boolean("performance", "smart_connectivity", "Smart connectivity"),
        text("performance", "included_accessories", "Included accessories"),
        text("notes", "warranty", "Warranty"),
      ]),
      sectionDef("Dimensions and power", [
        measurement("dimensions", "width", "Width", "in"),
        measurement("dimensions", "height", "Height", "in"),
        measurement("dimensions", "depth", "Depth", "in"),
        number("dimensions", "weight", "Weight", "lb"),
        number("electrical", "voltage", "Voltage", "V", "optional", { allowedUnits: ["V"], minimum: 0 }),
        number("electrical", "wattage", "Wattage", "W", "optional", { allowedUnits: ["W", "kW"], minimum: 0 }),
      ]),
    ]),
    general: template([], [
      sectionDef("General appliance", [
        measurement("dimensions", "width", "Width", "in"),
        measurement("dimensions", "height", "Height", "in"),
        measurement("dimensions", "depth", "Depth", "in"),
        number("dimensions", "weight", "Weight", "lb"),
        number("performance", "capacity", "Capacity", "cu. ft.", "optional", { allowedUnits: ["cu. ft.", "L", "loads", "place settings", "bottles"] }),
        number("electrical", "voltage", "Voltage", "V", "optional", { allowedUnits: ["V"], minimum: 0 }),
        number("electrical", "amperage", "Amperage", "A", "optional", { allowedUnits: ["A"], minimum: 0 }),
        number("electrical", "wattage", "Wattage", "W", "optional", { allowedUnits: ["W", "kW"], minimum: 0 }),
        text("configuration", "fuel_type", "Fuel type"),
        text("installation", "installation_type", "Installation type"),
        requirement("electrical", "electrical_requirements", "Electrical requirements"),
        text("installation", "water_requirements", "Water requirements"),
        gasRequirement("gas", "gas_requirements", "Gas requirements"),
        text("installation", "drain_requirements", "Drain requirements"),
        text("installation", "included_accessories", "Included accessories"),
        text("installation", "required_accessories", "Required accessories"),
        text("notes", "warranty", "Warranty"),
        text("notes", "additional_notes", "Additional notes"),
        boolean("certifications", "energy_star", "ENERGY STAR"),
        boolean("performance", "smart_connectivity", "Smart connectivity"),
      ]),
    ]),
  };
  const templateFor = category => {
    const lower = String(category || "").toLowerCase();
    const found = Object.entries(templates).find(([, templateDef]) => templateDef.match.some(match => lower.includes(match)));
    return found?.[0] || "general";
  };
  const templateDefinition = templateName => templates[templateName] || templates.general;
  const templateSections = templateName => clone(templateDefinition(templateName).sections);
  const templateFields = templateName => clone(templateDefinition(templateName).fields);
  const templateFieldMap = templateName => clone(templateDefinition(templateName).fieldMap);
  const normalizeStoredValue = (value) => {
    if (value == null) return { state: "empty", value: null, unit: "", raw: value };
    if (typeof value !== "object" || Array.isArray(value)) {
      return { state: "set", value, unit: "", raw: value, format: "legacy" };
    }
    if (value.status === "not_applicable") return { state: "not_applicable", value: null, unit: "", raw: value };
    if (Object.prototype.hasOwnProperty.call(value, "value")) {
      return { state: "set", value: value.value, unit: canonicalValue(value.unit || ""), raw: value, format: "structured" };
    }
    return { state: "set", value, unit: "", raw: value, format: "legacy_object" };
  };
  const displayStoredValue = (value) => {
    const normalized = normalizeStoredValue(value);
    if (normalized.state === "empty") return { text: "Not Yet Available", state: "empty" };
    if (normalized.state === "not_applicable") return { text: "Not applicable", state: "not_applicable" };
    if (Array.isArray(normalized.value)) return { text: normalized.value.map(item => String(item)).join(", "), state: "set", unit: normalized.unit };
    if (normalized.unit) return { text: `${normalized.value} ${normalized.unit}`, state: "set", unit: normalized.unit };
    return { text: String(normalized.value), state: "set", unit: normalized.unit };
  };
  const buildPayloadValue = (fieldDef, change) => {
    if (change.operation === "clear") return null;
    if (change.operation === "not_applicable") return { value: null, status: "not_applicable" };
    const unit = change.unit ? normalizeUnit(change.unit, fieldDef.allowedUnits) : "";
    if (fieldDef.fieldType === "boolean") return !!change.value;
    if (fieldDef.fieldType === "multi-select") return Array.isArray(change.value) ? change.value : [];
    if (fieldDef.fieldType === "number" || fieldDef.fieldType === "measurement") {
      const numeric = typeof change.value === "number" ? change.value : Number(change.value);
      return unit ? { value: numeric, unit } : numeric;
    }
    if (fieldDef.fieldType === "electrical requirement" || fieldDef.fieldType === "gas requirement") {
      return unit ? { value: change.value, unit } : change.value;
    }
    return unit ? { value: change.value, unit } : change.value;
  };
  const isEmptyChange = change => change == null || change.operation === "unchanged";
  const diffEntry = (fieldDef, current, next) => {
    if (next.operation === "clear") return current.state === "empty" ? null : next;
    if (next.operation === "not_applicable") return current.state === "not_applicable" ? null : next;
    const nextValue = normalizeStoredValue(buildPayloadValue(fieldDef, next));
    if (current.state === nextValue.state && String(current.value ?? "") === String(nextValue.value ?? "") && String(current.unit ?? "") === String(nextValue.unit ?? "")) return null;
    return next;
  };
  const collectKnownKeys = templateName => new Set(templateFields(templateName).map(field => `${field.group}.${field.key}`));
  const groupFields = templateName => templateSections(templateName).map(section => ({ ...section, fields: section.fields.slice().sort((a, b) => (a.displayOrder || 0) - (b.displayOrder || 0)) }));
  window.ProductIQSpecificationTemplates = templates;
  window.ProductIQTemplateNames = templateNames;
  window.ProductIQTemplateAliases = templateAliases;
  window.productIQTemplateFor = templateFor;
  window.productIQTemplateDefinition = templateDefinition;
  window.productIQTemplateSections = templateSections;
  window.productIQTemplateFields = templateFields;
  window.productIQTemplateFieldMap = templateFieldMap;
  window.productIQNormalizeStoredValue = normalizeStoredValue;
  window.productIQDisplayStoredValue = displayStoredValue;
  window.productIQBuildSpecificationValue = buildPayloadValue;
  window.productIQSpecificationDiffEntry = diffEntry;
  window.productIQKnownSpecificationKeys = collectKnownKeys;
  window.productIQGroupedSpecificationSections = groupFields;
})();
