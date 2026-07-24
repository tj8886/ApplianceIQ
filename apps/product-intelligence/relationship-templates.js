(() => {
  const slug = value => String(value || "").toLowerCase().trim().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");

  const groups = {
    accessories: "Accessories",
    pairings: "Product Pairings",
    compatibility: "Compatible Products",
    installation: "Installation Dependencies",
    replacement: "Replacement History",
    incompatible: "Incompatible Products",
    other: "Other Relationships",
  };

  const relationshipTypes = [
    { key: "accessory", label: "Accessory", group: "accessories", direction: "forward", bidirectional: false, activeLabel: "Accessory", inverseLabel: "Accessory" },
    { key: "required_accessory", label: "Required Accessory", group: "accessories", direction: "forward", bidirectional: false, activeLabel: "Requires", inverseLabel: "Required by" },
    { key: "optional_accessory", label: "Optional Accessory", group: "accessories", direction: "forward", bidirectional: false, activeLabel: "Optional accessory", inverseLabel: "Optional accessory" },
    { key: "compatible_with", label: "Compatible With", group: "compatibility", direction: "bidirectional", bidirectional: true, activeLabel: "Compatible with", inverseLabel: "Compatible with" },
    { key: "incompatible_with", label: "Incompatible With", group: "incompatible", direction: "bidirectional", bidirectional: true, activeLabel: "Incompatible with", inverseLabel: "Incompatible with" },
    { key: "replaces", label: "Replaces", group: "replacement", direction: "forward", bidirectional: false, activeLabel: "Replaces", inverseLabel: "Replaced by" },
    { key: "replaced_by", label: "Replaced By", group: "replacement", direction: "forward", bidirectional: false, activeLabel: "Replaced by", inverseLabel: "Replaces" },
    { key: "predecessor", label: "Predecessor", group: "replacement", direction: "forward", bidirectional: false, activeLabel: "Predecessor", inverseLabel: "Successor" },
    { key: "successor", label: "Successor", group: "replacement", direction: "forward", bidirectional: false, activeLabel: "Successor", inverseLabel: "Predecessor" },
    { key: "package_companion", label: "Package Companion", group: "pairings", direction: "bidirectional", bidirectional: true, activeLabel: "Package companion", inverseLabel: "Package companion" },
    { key: "installation_dependency", label: "Installation Dependency", group: "installation", direction: "forward", bidirectional: false, activeLabel: "Installation dependency", inverseLabel: "Installation dependency" },
    { key: "pedestal", label: "Pedestal", group: "accessories", direction: "forward", bidirectional: false, activeLabel: "Pedestal", inverseLabel: "Pedestal" },
    { key: "stacking_kit", label: "Stacking Kit", group: "accessories", direction: "forward", bidirectional: false, activeLabel: "Stacking kit", inverseLabel: "Stacking kit" },
    { key: "panel", label: "Panel", group: "accessories", direction: "forward", bidirectional: false, activeLabel: "Panel", inverseLabel: "Panel" },
    { key: "handle", label: "Handle", group: "accessories", direction: "forward", bidirectional: false, activeLabel: "Handle", inverseLabel: "Handle" },
    { key: "trim_kit", label: "Trim Kit", group: "accessories", direction: "forward", bidirectional: false, activeLabel: "Trim kit", inverseLabel: "Trim kit" },
    { key: "filter", label: "Filter", group: "accessories", direction: "forward", bidirectional: false, activeLabel: "Filter", inverseLabel: "Filter" },
    { key: "hose", label: "Hose", group: "accessories", direction: "forward", bidirectional: false, activeLabel: "Hose", inverseLabel: "Hose" },
    { key: "power_cord", label: "Power Cord", group: "installation", direction: "forward", bidirectional: false, activeLabel: "Power cord", inverseLabel: "Power cord" },
    { key: "ventilation_dependency", label: "Ventilation Dependency", group: "installation", direction: "forward", bidirectional: false, activeLabel: "Ventilation dependency", inverseLabel: "Ventilation dependency" },
    { key: "cooking_dependency", label: "Cooking Dependency", group: "installation", direction: "forward", bidirectional: false, activeLabel: "Cooking dependency", inverseLabel: "Cooking dependency" },
    { key: "laundry_pair", label: "Laundry Pair", group: "pairings", direction: "bidirectional", bidirectional: true, activeLabel: "Laundry pair", inverseLabel: "Laundry pair" },
    { key: "refrigeration_pair", label: "Refrigeration Pair", group: "pairings", direction: "bidirectional", bidirectional: true, activeLabel: "Refrigeration pair", inverseLabel: "Refrigeration pair" },
    { key: "outdoor_pair", label: "Outdoor Pair", group: "pairings", direction: "bidirectional", bidirectional: true, activeLabel: "Outdoor pair", inverseLabel: "Outdoor pair" },
    { key: "alternate_finish", label: "Alternate Finish", group: "compatibility", direction: "bidirectional", bidirectional: true, activeLabel: "Alternate finish", inverseLabel: "Alternate finish" },
    { key: "equivalent_model", label: "Equivalent Model", group: "compatibility", direction: "bidirectional", bidirectional: true, activeLabel: "Equivalent model", inverseLabel: "Equivalent model" },
    { key: "service_part", label: "Service Part", group: "other", direction: "forward", bidirectional: false, activeLabel: "Service part", inverseLabel: "Service part" },
    { key: "other", label: "Other", group: "other", direction: "forward", bidirectional: false, activeLabel: "Other", inverseLabel: "Other" },
  ];

  const typeMap = relationshipTypes.reduce((acc, entry) => {
    acc[entry.key] = entry;
    acc[slug(entry.label)] = entry;
    return acc;
  }, {});

  const aliasMap = {
    accessory: "accessory",
    accessories: "accessory",
    accessory_relation: "accessory",
    required: "required_accessory",
    required_accessory: "required_accessory",
    required_accessories: "required_accessory",
    optional: "optional_accessory",
    optional_accessory: "optional_accessory",
    optional_accessories: "optional_accessory",
    compatible: "compatible_with",
    compatible_with: "compatible_with",
    compatibility: "compatible_with",
    incompatible: "incompatible_with",
    incompatible_with: "incompatible_with",
    replace: "replaces",
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

  const categoryGuidance = {
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

  function normalizeRelationshipType(value) {
    const key = slug(value);
    return aliasMap[key] || key || "other";
  }

  function relationshipDefinition(value) {
    const key = normalizeRelationshipType(value);
    return typeMap[key] || typeMap.other;
  }

  function relationshipGroup(value) {
    return relationshipDefinition(value).group;
  }

  function relationshipLabel(value, perspective = "source") {
    const def = relationshipDefinition(value);
    return perspective === "target" ? def.inverseLabel : def.activeLabel;
  }

  function relationshipCategoryGuidance(category) {
    const key = slug(category);
    return categoryGuidance[key] || categoryGuidance.general;
  }

  window.ProductIQRelationshipTemplates = {
    groups,
    relationshipTypes,
    typeMap,
    aliasMap,
    normalizeRelationshipType,
    relationshipDefinition,
    relationshipGroup,
    relationshipLabel,
    relationshipCategoryGuidance,
  };
})();
