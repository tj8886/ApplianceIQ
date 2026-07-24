(() => {
  const templates = window.ProductIQRelationshipTemplates || {};
  const relationshipTypes = templates.relationshipTypes || [];
  const normalizeRelationshipType = templates.normalizeRelationshipType || (value => String(value || "").trim().toLowerCase());
  const relationshipDefinition = templates.relationshipDefinition || (value => ({ key: normalizeRelationshipType(value), label: String(value || ""), group: "other", direction: "forward", bidirectional: false, activeLabel: String(value || ""), inverseLabel: String(value || "") }));
  const relationshipGroup = templates.relationshipGroup || (value => relationshipDefinition(value).group);
  const relationshipLabel = templates.relationshipLabel || (value => String(value || ""));
  const relationshipCategoryGuidance = templates.relationshipCategoryGuidance || (() => []);

  const groupLabels = {
    required_accessories: "Required Accessories",
    optional_accessories: "Optional Accessories",
    compatible_products: "Compatible Products",
    product_pairings: "Product Pairings",
    installation_dependencies: "Installation Dependencies",
    replacement_history: "Replacement History",
    incompatible_products: "Incompatible Products",
    other_relationships: "Other Relationships",
  };

  const sectionFilters = {
    Relationships: Object.keys(groupLabels),
    Accessories: ["required_accessories", "optional_accessories"],
    "Compatible Products": ["compatible_products", "product_pairings"],
    "Replacement Models": ["replacement_history"],
    "Package Builder": ["product_pairings", "installation_dependencies"],
    "Cross Sell": ["compatible_products", "product_pairings", "other_relationships"],
    "Related Products": Object.keys(groupLabels),
  };

  const sectionTitles = {
    Relationships: "Relationships",
    Accessories: "Accessories",
    "Compatible Products": "Compatible products",
    "Replacement Models": "Replacement history",
    "Package Builder": "Package builder",
    "Cross Sell": "Cross sell",
    "Related Products": "Related products",
  };

  const relationshipSectionNames = Object.keys(sectionFilters);
  if (!workspaceSections.includes("Relationships")) {
    const insertAfter = workspaceSections.indexOf("Package Builder");
    workspaceSections.splice(insertAfter >= 0 ? insertAfter + 1 : workspaceSections.length, 0, "Relationships");
  }

  const originalSectionHtml = sectionHtml;
  const originalLoadWorkspaceSection = loadWorkspaceSection;

  const escAttr = value => String(value ?? "").replace(/"/g, "&quot;");

  const style = document.createElement("style");
  style.textContent = `
    .relationship-summary{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px;margin:14px 0}
    .relationship-card{display:grid;gap:10px;background:#fff;border:1px solid var(--line);border-radius:11px;padding:14px}
    .relationship-card.archived{opacity:.76}
    .relationship-head{display:flex;gap:10px;align-items:flex-start}
    .relationship-thumb{width:64px;height:64px;border-radius:10px;background:#eef2f6;overflow:hidden;display:grid;place-items:center;flex:0 0 auto}
    .relationship-thumb img{width:100%;height:100%;object-fit:cover}
    .relationship-body{min-width:0;display:grid;gap:2px}
    .relationship-title{font-weight:800;color:var(--navy)}
    .relationship-sub{font-size:12px;color:var(--muted)}
    .relationship-meta{display:flex;gap:6px;flex-wrap:wrap}
    .relationship-actions{display:flex;gap:8px;flex-wrap:wrap}
    .relationship-search-results{display:grid;gap:8px;max-height:260px;overflow:auto}
    .relationship-search-row{display:flex;justify-content:space-between;gap:12px;align-items:flex-start;border:1px solid var(--line);border-radius:9px;padding:10px;background:#fff}
    .relationship-selected{padding:10px;border:1px dashed #cad3df;border-radius:9px;background:#fbfcfd}
    @media(max-width:980px){.relationship-summary{grid-template-columns:repeat(2,minmax(0,1fr))}}
    @media(max-width:620px){.relationship-summary{grid-template-columns:1fr}}
  `;
  document.head.append(style);

  const relationshipGroupKey = row => {
    const type = normalizeRelationshipType(row.relationship_type);
    if (type === "required_accessory") return "required_accessories";
    if (["accessory", "optional_accessory", "pedestal", "stacking_kit", "panel", "handle", "trim_kit", "filter", "hose", "power_cord"].includes(type)) {
      return "optional_accessories";
    }
    if (["compatible_with", "equivalent_model", "alternate_finish"].includes(type)) return "compatible_products";
    if (["package_companion", "laundry_pair", "refrigeration_pair", "outdoor_pair"].includes(type)) return "product_pairings";
    if (["installation_dependency", "ventilation_dependency", "cooking_dependency"].includes(type)) return "installation_dependencies";
    if (["replaces", "replaced_by", "predecessor", "successor", "service_part"].includes(type)) return "replacement_history";
    if (type === "incompatible_with") return "incompatible_products";
    return "other_relationships";
  };

  const relationshipPerspective = (row, productId) => String(row.product_id) === String(productId) ? "source" : "target";
  const counterpartId = (row, productId) => String(row.product_id) === String(productId) ? row.related_product_id : row.product_id;

  const titleCase = value => String(value || "").replace(/_/g, " ").replace(/\b\w/g, c => c.toUpperCase());

  const groupBy = (rows, keyFn) => rows.reduce((acc, row) => {
    const key = keyFn(row);
    if (!acc[key]) acc[key] = [];
    acc[key].push(row);
    return acc;
  }, {});

  const normalizeTargetProduct = row => ({
    id: row.id,
    manufacturer_name: row.manufacturer_name,
    brand_name: row.brand_name,
    model: row.model,
    short_description: row.short_description,
    category: row.category,
    status: row.status,
    approval_status: row.approval_status,
    public_visible: row.public_visible,
    version_number: row.version_number,
    updated_at: row.updated_at,
  });

  function relationshipActiveLabel(row, productId) {
    return relationshipLabel(row.relationship_type, relationshipPerspective(row, productId));
  }

  function relationshipTargetCard(row, product, relatedProductMap, primaryImageMap) {
    const otherId = counterpartId(row, product.id);
    const other = relatedProductMap[otherId];
    const image = primaryImageMap[otherId];
    const archived = !!row.archived_at;
    const group = groupLabels[relationshipGroupKey(row)] || "Other Relationships";
    const labels = [
      pill(group, "blue"),
      pill(relationshipActiveLabel(row, product.id), archived ? "gray" : "green"),
      pill(titleCase(row.requirement_level || "optional"), row.requirement_level === "required" ? "amber" : "gray"),
      pill(titleCase(row.compatibility_status || "unverified"), row.compatibility_status === "verified" ? "green" : row.compatibility_status === "incompatible" ? "red" : "gray"),
      archived ? pill("Archived", "gray") : pill("Active", "green"),
      row.direction ? pill(titleCase(row.direction), "gray") : "",
    ].filter(Boolean).join("");
    const targetTitle = other ? `${other.brand_name || "—"} ${other.model || "—"}` : `Product ${otherId}`;
    const targetSubtitle = other ? `${other.manufacturer_name || "—"} · ${other.category || "—"}` : "Target product unavailable or not visible";
    const sourceLine = row.source_reference || row.source_type ? `${row.source_type || "internal"}${row.source_reference ? ` · ${row.source_reference}` : ""}` : "—";
    const notes = [row.compatibility_notes, row.installation_notes].filter(Boolean).join(" · ");
    return `<div class="relationship-card ${archived ? "archived" : ""}">
      <div class="relationship-head">
        <div class="relationship-thumb">${image?.file_url || image?.media_url ? `<img src="${esc(image.file_url || image.media_url)}" alt="${esc(other?.model || row.relationship_label || "Related product")}" loading="lazy" />` : `<div class="placeholder">□</div>`}</div>
        <div class="relationship-body">
          <div class="relationship-meta">${labels}</div>
          <div class="relationship-title">${esc(targetTitle)}</div>
          <div class="relationship-sub">${esc(targetSubtitle)}</div>
          <div class="relationship-sub">Model ${esc(other?.model || "—")} · ${esc(row.relationship_label || relationshipLabel(row.relationship_type))}</div>
          <div class="relationship-sub">${row.quantity != null ? `Quantity ${esc(row.quantity)}` : "Quantity —"}${row.minimum_quantity != null ? ` · Min ${esc(row.minimum_quantity)}` : ""}${row.maximum_quantity != null ? ` · Max ${esc(row.maximum_quantity)}` : ""}</div>
          <div class="relationship-sub">${notes ? esc(notes) : "No relationship notes"}</div>
          <div class="relationship-sub">${sourceLine !== "—" ? esc(sourceLine) : "No source attribution"}${row.source_confidence != null ? ` · Confidence ${esc(row.source_confidence)}%` : ""}${row.effective_start_date || row.effective_end_date ? ` · ${esc(row.effective_start_date || "—")} → ${esc(row.effective_end_date || "—")}` : ""}</div>
        </div>
      </div>
      <div class="relationship-actions">
        ${other ? `<button type="button" class="btn secondary" onclick="go('products/${esc(other.id)}')">Open product</button>` : ""}
        ${isPlatformUser() ? `<button type="button" class="btn secondary" onclick="openRelationshipEditor('${esc(product.id)}','${esc(row.id)}')">Edit</button>
        <button type="button" class="btn secondary" onclick="${archived ? `restoreRelationship('${esc(product.id)}','${esc(row.id)}')` : `archiveRelationship('${esc(product.id)}','${esc(row.id)}')`}">${archived ? "Restore" : "Archive"}</button>` : ""}
      </div>
    </div>`;
  }

  function relationshipSectionSummary(rows) {
    const summary = {
      required_accessories: 0,
      optional_accessories: 0,
      compatible_products: 0,
      product_pairings: 0,
      installation_dependencies: 0,
      replacement_history: 0,
      incompatible_products: 0,
      other_relationships: 0,
    };
    for (const row of rows || []) summary[relationshipGroupKey(row)]++;
    return Object.entries(summary).map(([key, count]) => `<div class="workspace-stat"><small>${esc(groupLabels[key])}</small><b>${esc(count)}</b></div>`).join("");
  }

  function renderRelationshipGroups(section, data, product) {
    const rows = (Array.isArray(data) ? data : data?.data || data?.rows || []).slice();
    const productMap = data?.productMap || {};
    const primaryImageMap = data?.primaryImageMap || {};
    const allowedGroups = sectionFilters[section] || Object.keys(groupLabels);
    const visible = rows.filter(row => allowedGroups.includes(relationshipGroupKey(row)));
    const active = visible.filter(row => !row.archived_at);
    const archived = visible.filter(row => row.archived_at);
    const grouped = groupBy(active, relationshipGroupKey);
    const archivedGrouped = groupBy(archived, relationshipGroupKey);
    const groupOrder = allowedGroups;
    const groupMarkup = (source, archivedMode = false) => groupOrder.map(key => {
      const items = source[key] || [];
      if (!items.length) return "";
      return `<div class="doc-group">
        <div class="doc-group-head">
          <h3>${esc(groupLabels[key])}</h3>
          <span class="tiny">${items.length} record${items.length === 1 ? "" : "s"}</span>
        </div>
        <div class="data-list">${items.map(row => relationshipTargetCard(row, product, productMap, primaryImageMap)).join("")}</div>
      </div>`;
    }).filter(Boolean).join("");

    const suggestedTypes = relationshipCategoryGuidance(product.category)
      .map(type => `<span class="pill gray">${esc(relationshipLabel(type))}</span>`)
      .join("");
    return `<div class="data-card">
      <div class="section-title">
        <h2>${esc(sectionTitles[section] || section)}</h2>
        <div class="split-actions">${isPlatformUser() ? `<button type="button" class="btn primary" onclick="addRelationship('${escAttr(product.id)}')">Add relationship</button>` : ""}</div>
      </div>
      <div class="workspace-note">Relationship rows are grouped by compatibility and dependency meaning rather than a generic related-products list.</div>
      ${suggestedTypes ? `<div class="relationship-meta" style="margin:10px 0 14px">${suggestedTypes}</div>` : ""}
      <div class="workspace-stats" style="margin-top:0">${relationshipSectionSummary(visible)}</div>
      <div class="doc-type-group" style="margin-top:16px">${groupMarkup(groupBy(active, relationshipGroupKey)) || `<div class="empty">No active ${esc(section.toLowerCase())} relationships are recorded.</div>`}</div>
      ${archived.length ? `<details class="asset-archive" style="margin-top:12px"><summary class="hidden-toggle"><span class="pill gray">Show archived relationships</span></summary><div class="doc-type-group" style="margin-top:12px">${groupMarkup(groupBy(archived, relationshipGroupKey), true) || `<div class="empty">No archived relationships.</div>`}</div></details>` : ""}
    </div>`;
  }

  function conflictMarkup(loadedVersion, currentVersion, updatedAt, updatedBy) {
    return `<div class="conflict-panel">
      <b>Another update was saved first.</b>
      <div class="workspace-note">Loaded version ${esc(loadedVersion)} · Current version ${esc(currentVersion)}${updatedAt ? ` · Updated ${esc(formatDate(updatedAt))}` : ""}${updatedBy ? ` · By ${esc(updatedBy)}` : ""}</div>
      <div class="conflict-actions">
        <button type="button" class="btn secondary" data-reload>Reload latest</button>
        <button type="button" class="btn secondary" data-continue>Continue reviewing unsaved values</button>
        <button type="button" class="btn secondary" data-copy>Copy unsaved values</button>
      </div>
    </div>`;
  }

  function buildRelationshipTypeOptions(selected) {
    return relationshipTypes.map(type => `<option value="${esc(type.key)}" ${normalizeRelationshipType(selected) === type.key ? "selected" : ""}>${esc(type.label)}</option>`).join("");
  }

  function relationshipFormMarkup(product, relationship, relatedProduct, selectedTarget, isCreate) {
    const baseline = relationship ? {
      relationship_type: normalizeRelationshipType(relationship.relationship_type),
      direction: relationship.direction || relationshipDefinition(relationship.relationship_type).direction,
      requirement_level: relationship.requirement_level || "optional",
      compatibility_status: relationship.compatibility_status || "unverified",
      compatibility_notes: relationship.compatibility_notes || relationship.notes || "",
      installation_notes: relationship.installation_notes || "",
      quantity: relationship.quantity ?? "",
      minimum_quantity: relationship.minimum_quantity ?? "",
      maximum_quantity: relationship.maximum_quantity ?? "",
      same_brand_requirement: !!relationship.same_brand_requirement,
      compatible_finish_requirement: !!relationship.compatible_finish_requirement,
      source_type: relationship.source_type || "",
      source_reference: relationship.source_reference || "",
      source_confidence: relationship.source_confidence ?? "",
      effective_start_date: relationship.effective_start_date || "",
      effective_end_date: relationship.effective_end_date || "",
    } : {
      relationship_type: "",
      direction: "",
      requirement_level: "",
      compatibility_status: "",
      compatibility_notes: "",
      installation_notes: "",
      quantity: "",
      minimum_quantity: "",
      maximum_quantity: "",
      same_brand_requirement: false,
      compatible_finish_requirement: false,
      source_type: "",
      source_reference: "",
      source_confidence: "",
      effective_start_date: "",
      effective_end_date: "",
    };
    const selectedSummary = selectedTarget ? `<div class="relationship-selected"><b>${esc(selectedTarget.brand_name || "—")} ${esc(selectedTarget.model || "—")}</b><div class="tiny">${esc(selectedTarget.manufacturer_name || "—")} · ${esc(selectedTarget.category || "—")}</div><div class="tiny">${esc(selectedTarget.short_description || "")}</div>${selectedTarget.id ? `<div class="tiny">Product ID ${esc(selectedTarget.id)}</div>` : ""}</div>` : `<div class="empty-inline">Search for a target product to continue.</div>`;
    return `<form id="relationship-form">
      <input type="hidden" name="original_version" value="${esc(product.version_number)}" />
      <input type="hidden" name="relationship_id" value="${relationship?.id ? esc(relationship.id) : ""}" />
      <input type="hidden" name="related_product_id" value="${selectedTarget?.id || relationship?.related_product_id || ""}" />
      <div class="modal-grid">
        ${isCreate ? `
        <div class="full relationship-search">
          <div class="section-title"><h3>Target product</h3><span class="tiny">Search by model number, product name, or brand</span></div>
          <div class="modal-grid">
            ${fieldControlWithError("target_query", "Search", `<input class="control" name="target_query" placeholder="Search products…" autocomplete="off" />`, "Use the search button or type to filter.", false)}
            ${fieldControlWithError("target_brand", "Brand filter", `<input class="control" name="target_brand" placeholder="Optional brand" autocomplete="off" />`)}
            ${fieldControlWithError("target_category", "Category filter", `<input class="control" name="target_category" placeholder="Optional category" autocomplete="off" />`)}
            <div class="full"><button type="button" class="btn secondary" data-search>Search products</button></div>
          </div>
          <div id="relationship-search-results" class="relationship-search-results"></div>
          <div id="relationship-selected-target" class="full">${selectedSummary}</div>
        </div>` : `<div class="full relationship-selected"><b>Target product</b><div class="tiny">${esc(relatedProduct?.brand_name || "—")} ${esc(relatedProduct?.model || "—")}</div><div class="tiny">${esc(relatedProduct?.manufacturer_name || "—")} · ${esc(relatedProduct?.category || "—")}</div><div class="tiny">${esc(relatedProduct?.short_description || "")}</div><div class="tiny">Change the target product by creating a new relationship.</div></div>`}
        ${fieldControlWithError("relationship_type", "Relationship type", `<select class="control" name="relationship_type">${buildRelationshipTypeOptions(baseline.relationship_type)}</select>`, "Controlled vocabulary only.", true)}
        ${fieldControlWithError("requirement_level", "Requirement level", `<select class="control" name="requirement_level"><option value="">Select…</option><option value="required" ${baseline.requirement_level === "required" ? "selected" : ""}>Required</option><option value="recommended" ${baseline.requirement_level === "recommended" ? "selected" : ""}>Recommended</option><option value="optional" ${baseline.requirement_level === "optional" ? "selected" : ""}>Optional</option><option value="not_applicable" ${baseline.requirement_level === "not_applicable" ? "selected" : ""}>Not applicable</option></select>`)}
        ${fieldControlWithError("compatibility_status", "Compatibility status", `<select class="control" name="compatibility_status"><option value="">Select…</option><option value="verified" ${baseline.compatibility_status === "verified" ? "selected" : ""}>Verified</option><option value="likely" ${baseline.compatibility_status === "likely" ? "selected" : ""}>Likely</option><option value="conditional" ${baseline.compatibility_status === "conditional" ? "selected" : ""}>Conditional</option><option value="incompatible" ${baseline.compatibility_status === "incompatible" ? "selected" : ""}>Incompatible</option><option value="unverified" ${baseline.compatibility_status === "unverified" ? "selected" : ""}>Unverified</option><option value="discontinued" ${baseline.compatibility_status === "discontinued" ? "selected" : ""}>Discontinued</option><option value="not_applicable" ${baseline.compatibility_status === "not_applicable" ? "selected" : ""}>Not applicable</option></select>`, "Conditional compatibility requires notes.")} 
        ${fieldControlWithError("quantity", "Quantity", `<input class="control" name="quantity" type="number" min="1" step="1" value="${esc(baseline.quantity)}" />`, "Use for accessories and dependencies where a quantity applies.")}        
        ${fieldControlWithError("minimum_quantity", "Minimum quantity", `<input class="control" name="minimum_quantity" type="number" min="1" step="1" value="${esc(baseline.minimum_quantity)}" />`)}
        ${fieldControlWithError("maximum_quantity", "Maximum quantity", `<input class="control" name="maximum_quantity" type="number" min="1" step="1" value="${esc(baseline.maximum_quantity)}" />`)}
        ${fieldControlWithError("source_type", "Source", `<select class="control" name="source_type"><option value="">Select…</option><option value="internal" ${baseline.source_type === "internal" ? "selected" : ""}>Internal</option><option value="manufacturer_submitted" ${baseline.source_type === "manufacturer_submitted" ? "selected" : ""}>Manufacturer submitted</option><option value="raw_import" ${baseline.source_type === "raw_import" ? "selected" : ""}>Raw import</option><option value="ai_extracted" ${baseline.source_type === "ai_extracted" ? "selected" : ""}>AI extracted</option><option value="ai_suggested" ${baseline.source_type === "ai_suggested" ? "selected" : ""}>AI suggested</option><option value="aiq_reviewed" ${baseline.source_type === "aiq_reviewed" ? "selected" : ""}>ApplianceIQ reviewed</option></select>`)}
        ${fieldControlWithError("source_reference", "Source reference", `<input class="control" name="source_reference" value="${esc(baseline.source_reference)}" />`)}
        ${fieldControlWithError("source_confidence", "Source confidence", `<input class="control" name="source_confidence" type="number" min="0" max="100" step="0.01" value="${esc(baseline.source_confidence)}" />`, "Confidence is stored as a percentage.")}        
        ${fieldControlWithError("effective_start_date", "Effective start date", `<input class="control" name="effective_start_date" type="date" value="${esc(baseline.effective_start_date)}" />`)}
        ${fieldControlWithError("effective_end_date", "Effective end date", `<input class="control" name="effective_end_date" type="date" value="${esc(baseline.effective_end_date)}" />`)}
        ${fieldControlWithError("same_brand_requirement", "Same-brand requirement", `<label class="toggle-row"><input type="checkbox" name="same_brand_requirement" ${baseline.same_brand_requirement ? "checked" : ""} /> Same brand required</label>`)}
        ${fieldControlWithError("compatible_finish_requirement", "Compatible finish requirement", `<label class="toggle-row"><input type="checkbox" name="compatible_finish_requirement" ${baseline.compatible_finish_requirement ? "checked" : ""} /> Compatible finish required</label>`)}
        <label class="field full" data-field="compatibility_notes"><small>Compatibility notes</small><textarea class="control" name="compatibility_notes" rows="4">${esc(baseline.compatibility_notes)}</textarea><div class="hint">Required when compatibility is conditional.</div><div class="field-error" data-field-error="compatibility_notes" hidden></div></label>
        <label class="field full" data-field="installation_notes"><small>Installation notes</small><textarea class="control" name="installation_notes" rows="3">${esc(baseline.installation_notes)}</textarea><div class="field-error" data-field-error="installation_notes" hidden></div></label>
      </div>
      <div id="relationship-conflict"></div>
      <div id="relationship-field-errors" class="error" hidden></div>
      <div class="modal-actions">
        <button type="button" class="btn secondary" data-close>Cancel</button>
        <button type="submit" class="btn primary">${relationship ? "Save relationship" : "Create relationship"}</button>
      </div>
    </form>`;
  }

  async function searchRelationshipProducts(host, product, form) {
    const results = host.querySelector("#relationship-search-results");
    if (!results) return;
    results.innerHTML = `<div class="loading">Searching…</div>`;
    const query = String(form.elements.target_query?.value || "").trim();
    const brand = String(form.elements.target_brand?.value || "").trim();
    const category = String(form.elements.target_category?.value || "").trim();
    const { data, error } = await sb.functions.invoke("product-iq-governance", {
      body: {
        action: "search_relationship_products",
        productId: product.id,
        query,
        brand,
        category,
        limit: 12,
        offset: 0,
        excludeProductId: product.id,
      },
    });
    if (error || data?.error) {
      results.innerHTML = `<div class="error">${esc(data?.error || error?.message || "Search failed.")}</div>`;
      return;
    }
    const rows = data?.data || data?.results || [];
    if (!rows.length) {
      results.innerHTML = `<div class="empty">No matching products were found.</div>`;
      return;
    }
    results.innerHTML = rows.map(row => `<div class="relationship-search-row">
      <div>
        <b>${esc(row.brand_name || "—")} ${esc(row.model || "—")}</b>
        <div class="tiny">${esc(row.manufacturer_name || "—")} · ${esc(row.category || "—")}</div>
        <div class="tiny">${esc(row.short_description || "")}</div>
      </div>
      <div style="text-align:right">
        <div class="tiny">${esc(row.status || "—")} · ${esc(row.approval_status || "—")}</div>
        <button type="button" class="btn secondary" data-use-target="${esc(row.id)}">Use</button>
      </div>
    </div>`).join("");
    results.querySelectorAll("[data-use-target]").forEach(button => {
      button.onclick = () => {
        const id = button.getAttribute("data-use-target");
        const selected = rows.find(row => String(row.id) === String(id));
        const targetField = form.elements.related_product_id;
        if (targetField) targetField.value = id;
        const selectedBox = host.querySelector("#relationship-selected-target");
        if (selectedBox) {
          selectedBox.innerHTML = `<div class="relationship-selected"><b>${esc(selected.brand_name || "—")} ${esc(selected.model || "—")}</b><div class="tiny">${esc(selected.manufacturer_name || "—")} · ${esc(selected.category || "—")}</div><div class="tiny">${esc(selected.short_description || "")}</div><div class="tiny">Product ID ${esc(selected.id)}</div></div>`;
        }
      };
    });
  }

  function relationshipFormValues(form) {
    return {
      relationship_type: String(form.elements.relationship_type?.value || "").trim(),
      requirement_level: String(form.elements.requirement_level?.value || "").trim(),
      compatibility_status: String(form.elements.compatibility_status?.value || "").trim(),
      quantity: String(form.elements.quantity?.value || "").trim(),
      minimum_quantity: String(form.elements.minimum_quantity?.value || "").trim(),
      maximum_quantity: String(form.elements.maximum_quantity?.value || "").trim(),
      same_brand_requirement: !!form.elements.same_brand_requirement?.checked,
      compatible_finish_requirement: !!form.elements.compatible_finish_requirement?.checked,
      compatibility_notes: String(form.elements.compatibility_notes?.value || "").trim(),
      installation_notes: String(form.elements.installation_notes?.value || "").trim(),
      source_type: String(form.elements.source_type?.value || "").trim(),
      source_reference: String(form.elements.source_reference?.value || "").trim(),
      source_confidence: String(form.elements.source_confidence?.value || "").trim(),
      effective_start_date: String(form.elements.effective_start_date?.value || "").trim(),
      effective_end_date: String(form.elements.effective_end_date?.value || "").trim(),
      related_product_id: String(form.elements.related_product_id?.value || "").trim(),
    };
  }

  function relationshipChangesFromValues(values, baseline, isCreate) {
    const changes = {};
    const mapping = {
      relationship_type: "relationship_type",
      requirement_level: "requirement_level",
      compatibility_status: "compatibility_status",
      quantity: "quantity",
      minimum_quantity: "minimum_quantity",
      maximum_quantity: "maximum_quantity",
      same_brand_requirement: "same_brand_requirement",
      compatible_finish_requirement: "compatible_finish_requirement",
      compatibility_notes: "compatibility_notes",
      installation_notes: "installation_notes",
      source_type: "source_type",
      source_reference: "source_reference",
      source_confidence: "source_confidence",
      effective_start_date: "effective_start_date",
      effective_end_date: "effective_end_date",
    };
    const normalizedBaseline = baseline || {};
    for (const [key, targetKey] of Object.entries(mapping)) {
      const current = values[key];
      const base = normalizedBaseline[key];
      if (isCreate || String(current ?? "") !== String(base ?? "")) changes[targetKey] = current;
    }
    return changes;
  }

  function relationshipConflictBody(loadedVersion, currentVersion, updatedAt, updatedBy) {
    return conflictMarkup(loadedVersion, currentVersion, updatedAt, updatedBy);
  }

  async function openRelationshipEditor(product, relationship = null) {
    const isCreate = !relationship;
    const relatedRow = relationship ? relationship : null;
    const relatedProductId = relatedRow ? counterpartId(relatedRow, product.id) : "";
    let selectedTarget = null;
    let relatedProduct = null;
    if (relatedProductId) {
      const { data } = await sb.from("aiq_products").select("id,manufacturer_name,brand_name,model,short_description,category,status,approval_status,public_visible,version_number,updated_at").eq("id", relatedProductId).maybeSingle();
      relatedProduct = data || null;
      selectedTarget = relatedProduct;
    }
    const modal = modalForm(isCreate ? "Add relationship" : "Edit relationship", `${product.brand_name} · ${product.model}`, relationshipFormMarkup(product, relationship, relatedProduct, selectedTarget, isCreate));
    const form = modal.modal.querySelector("#relationship-form");
    const conflictSlot = modal.modal.querySelector("#relationship-conflict");
    const errorBox = modal.modal.querySelector("#relationship-field-errors");
    const baseline = relationship ? relationshipFormValues(form) : {};
    let searchTimer = null;
    let dirty = false;

    const closeEditor = () => {
      if (dirty && !confirm("Discard unsaved relationship changes?")) return;
      clearEditorGuard();
      modal.close();
    };
    modal.modal.querySelectorAll("[data-close]").forEach(el => el.onclick = closeEditor);
    modal.modal.querySelector("[data-search]")?.addEventListener("click", () => searchRelationshipProducts(modal.modal, product, form));
    form.querySelectorAll("input,select,textarea").forEach(el => {
      el.addEventListener("input", () => {
        dirty = true;
        updateDirtyGuard(true, "relationship changes", closeEditor);
      });
      el.addEventListener("change", () => {
        dirty = true;
        updateDirtyGuard(true, "relationship changes", closeEditor);
      });
    });
    const queueSearch = () => {
      if (!isCreate) return;
      clearTimeout(searchTimer);
      searchTimer = setTimeout(() => searchRelationshipProducts(modal.modal, product, form), 220);
    };
    ["target_query", "target_brand", "target_category"].forEach(name => form.elements[name]?.addEventListener("input", queueSearch));
    if (isCreate && form.elements.target_query?.value) queueSearch();

    form.onsubmit = async event => {
      event.preventDefault();
      clearFieldErrors(form);
      errorBox.hidden = true;
      errorBox.textContent = "";
      const values = relationshipFormValues(form);
      if (isCreate && !values.related_product_id) {
        errorBox.hidden = false;
        errorBox.textContent = "Choose a target product before saving.";
        return;
      }
      const currentVersion = Number(form.elements.original_version.value);
      const changes = relationshipChangesFromValues(values, baseline, isCreate);
      if (!Object.keys(changes).length && !isCreate) {
        errorBox.hidden = false;
        errorBox.textContent = "No relationship changes were supplied.";
        return;
      }
      if (isCreate) {
        changes.relationship_type = values.relationship_type;
      }
      const submit = form.querySelector('[type="submit"]');
      submit.disabled = true;
      submit.textContent = isCreate ? "Creating…" : "Saving…";
      const payload = {
        productId: product.id,
        originalVersion: currentVersion,
        section: "relationships",
        reason: "",
        changes,
      };
      if (isCreate) payload.targetProductId = values.related_product_id;
      if (!isCreate) payload.relationshipId = relationship.id;
      const action = isCreate ? "create_product_relationship" : "update_product_relationship";
      const { data, error } = await sb.functions.invoke("product-iq-governance", { body: { action, ...payload } });
      if (error || data?.error) {
        submit.disabled = false;
        submit.textContent = isCreate ? "Create relationship" : "Save relationship";
        if (data?.code === "conflict" || data?.error === "conflict") {
          conflictSlot.innerHTML = relationshipConflictBody(payload.originalVersion, data.currentVersion, data.updatedAt, data.updatedBy);
          conflictSlot.querySelector("[data-reload]").onclick = async () => {
            if (isCreate) {
              const { data: fresh } = await sb.from("aiq_products").select("version_number,updated_at,updated_by").eq("id", product.id).maybeSingle();
              if (fresh) form.elements.original_version.value = fresh.version_number;
              conflictSlot.innerHTML = "";
              return;
            }
            const { data: freshProduct } = await sb.from("aiq_products").select("*").eq("id", product.id).maybeSingle();
            const { data: freshRelationship } = await sb.from("aiq_product_relationships").select("*").eq("id", relationship.id).maybeSingle();
            modal.close();
            if (freshProduct && freshRelationship) openRelationshipEditor(freshProduct, freshRelationship);
          };
          conflictSlot.querySelector("[data-continue]").onclick = () => { conflictSlot.innerHTML = ""; };
          conflictSlot.querySelector("[data-copy]").onclick = () => copyText(JSON.stringify({ currentVersion: data.currentVersion, submittedVersion: payload.originalVersion, values }, null, 2));
          return;
        }
        if (data?.fieldErrors) {
          applyFieldErrors(form, data.fieldErrors);
          errorBox.hidden = false;
          errorBox.textContent = data?.error || "Fix the highlighted relationship errors before saving.";
          return;
        }
        errorBox.hidden = false;
        errorBox.textContent = data?.error || error?.message || "Save failed.";
        return;
      }
      clearEditorGuard();
      modal.close();
      refreshProductView(product.id);
    };
  }

  async function archiveRelationship(productId, relationshipId) {
    if (!confirm("Archive this relationship? It will remain recoverable.")) return;
    const { data: product } = await sb.from("aiq_products").select("version_number").eq("id", productId).maybeSingle();
    const { data, error } = await sb.functions.invoke("product-iq-governance", { body: { action: "archive_product_relationship", productId, relationshipId, originalVersion: product?.version_number, section: "relationships" } });
    if (error || data?.error) return alert(data?.error || error?.message || "Unable to archive relationship.");
    refreshProductView(productId);
  }

  async function restoreRelationship(productId, relationshipId) {
    const { data: product } = await sb.from("aiq_products").select("version_number").eq("id", productId).maybeSingle();
    const { data, error } = await sb.functions.invoke("product-iq-governance", { body: { action: "restore_product_relationship", productId, relationshipId, originalVersion: product?.version_number, section: "relationships" } });
    if (error || data?.error) return alert(data?.error || error?.message || "Unable to restore relationship.");
    refreshProductView(productId);
  }

  sectionHtml = function (section, data, product, counts) {
    if (relationshipSectionNames.includes(section)) return renderRelationshipGroups(section, data, product, counts);
    return originalSectionHtml(section, data, product, counts);
  };

  loadWorkspaceSection = async function (id, section, product) {
    if (!relationshipSectionNames.includes(section)) return originalLoadWorkspaceSection(id, section, product);
    const key = `${id}:${section}`;
    if (workspaceCache.has(key)) return workspaceCache.get(key);
    const { data: rows, error } = await sb.from("aiq_product_relationships").select("*").or(`product_id.eq.${id},related_product_id.eq.${id}`).order("updated_at", { ascending: false });
    if (error) {
      const result = { error };
      workspaceCache.set(key, result);
      return result;
    }
    const ids = [...new Set((rows || []).flatMap(row => [row.product_id, row.related_product_id]).filter(Boolean).map(String))];
    const productColumns = "id,manufacturer_name,brand_name,model,short_description,category,status,approval_status,public_visible,version_number,updated_at";
    const [productsResult, imagesResult] = await Promise.all([
      ids.length ? sb.from("aiq_products").select(productColumns).in("id", ids) : Promise.resolve({ data: [] }),
      ids.length ? sb.from("mfr_assets").select("product_id,file_url,media_url,title,image_type,is_primary,archived_at").in("product_id", ids).eq("is_primary", true).is("archived_at", null) : Promise.resolve({ data: [] }),
    ]);
    const productMap = Object.fromEntries((productsResult.data || []).map(row => [row.id, row]));
    const primaryImageMap = Object.fromEntries((imagesResult.data || []).map(row => [row.product_id, row]));
    const result = { data: rows || [], rows: rows || [], productMap, primaryImageMap };
    workspaceCache.set(key, result);
    return result;
  };

  window.openRelationshipEditor = async (productId, relationshipId = null) => {
    const { data: product } = await sb.from("aiq_products").select("*").eq("id", productId).maybeSingle();
    if (!product) return alert("Product not found.");
    if (!relationshipId) return openRelationshipEditor(product, null);
    const { data: relationship } = await sb.from("aiq_product_relationships").select("*").eq("id", relationshipId).maybeSingle();
    if (!relationship) return alert("Relationship not found.");
    return openRelationshipEditor(product, relationship);
  };

  window.addRelationship = async productId => {
    const { data: product } = await sb.from("aiq_products").select("*").eq("id", productId).maybeSingle();
    if (!product) return alert("Product not found.");
    return openRelationshipEditor(product, null);
  };

  window.archiveRelationship = archiveRelationship;
  window.restoreRelationship = restoreRelationship;
  window.searchRelationshipProducts = searchRelationshipProducts;

  if (state.user) render();
})();
