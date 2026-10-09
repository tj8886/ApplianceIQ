// Strict preview contract: lossless string IDs, CAD/USD shop-money amounts, no invented costs.
const id=v=>{if(typeof v!=='string'||!/^[1-9][0-9]{0,24}$/.test(v))throw Error('invalid_external_id');return v;};
const money=v=>{if(typeof v!=='string'||!/^(0|[1-9][0-9]{0,11})(\.[0-9]{1,2})?$/.test(v))throw Error('invalid_money');const [whole,fraction='']=v.split('.');return BigInt(whole)*100n+BigInt(fraction.padEnd(2,'0'));};
const decimal=v=>{const negative=v<0n;const a=negative?-v:v;return (negative?'-':'')+(a/100n)+'.'+String(a%100n).padStart(2,'0');};
export function previewOrder(order){
 if(!order||typeof order!=='object'||Array.isArray(order)||!['CAD','USD'].includes(order.currency))throw Error('unsupported_currency_or_order');
 const orderId=id(order.id);if(!Array.isArray(order.line_items)||order.line_items.length<1||order.line_items.length>250)throw Error('invalid_lines');
 const seen=new Set();let gross=0n,discount=0n;const lines=order.line_items.map(line=>{
  if(!line||typeof line!=='object'||Array.isArray(line))throw Error('invalid_line');const lineId=id(line.id);
  if(seen.has(lineId))throw Error('duplicate_line');seen.add(lineId);
  if(!Number.isSafeInteger(line.quantity)||line.quantity<1||line.quantity>1000000)throw Error('invalid_quantity');
  const price=money(line.price),deduction=money(line.total_discount),amount=price*BigInt(line.quantity);
  if(deduction>amount)throw Error('discount_exceeds_line');gross+=amount;discount+=deduction;
  return {external_line_id:lineId,quantity:line.quantity,unit_price:decimal(price),discount_amount:decimal(deduction),line_amount:decimal(amount-deduction),unit_cost:null,line_cost:null,gross_margin_amount:null,gross_margin_pct:null};
 });
 const subtotal=money(order.subtotal_price),totalDiscount=money(order.total_discounts),tax=money(order.total_tax),total=money(order.total_price),shippingMoney=order.total_shipping_price_set?.shop_money;
 if(!shippingMoney||shippingMoney.currency_code!==order.currency)throw Error('shipping_currency_required');
 const shipping=money(shippingMoney.amount);
 if(gross-discount!==subtotal||discount!==totalDiscount||subtotal+tax+shipping!==total)throw Error('order_totals_require_reconciliation');
 return {external_order_id:orderId,currency:order.currency,line_count:lines.length,subtotal:decimal(subtotal),discount_amount:decimal(discount),tax_amount:decimal(tax),shipping_amount:decimal(shipping),total:decimal(total),cost_amount:null,gross_margin_amount:null,gross_margin_pct:null,lines};
}
