#!/usr/bin/env python3
"""Generate synthetic PDF test fixtures for parser tests.

Creates two PDFs with fake data that match the exact format the parsers expect.
All names, emails, phones, and addresses are entirely synthetic.

Usage:
    python3 test/fixtures/generate_fixtures.py
"""

import random
from fpdf import FPDF

# ─── Shared helpers ──────────────────────────────────────────────────────────

def _phone(area: str, mid: str, last: str) -> str:
    return f"{area}-{mid}-{last}"


# ─── JD Sweid fixture ───────────────────────────────────────────────────────
#
# Target: 28 orders, 25 customers after consolidation, 99 total boxes.
#
# The Syncfusion PDF text extractor produces line-by-line output.
# The parser splits on "SUPPORTER PRODUCTS ORDERED" and parses each block.
# Within a block it finds (in order):
#   - name (first line that looks like a name)
#   - email (regex: [\w.+-]+@[\w.-]+\.\w+)
#   - phone (10-11 digit line without $ or "Order")
#   - Order ID: XXXXX
#   - product lines: "ProductName (SKU)" then standalone qty on next line
#   - "# OF BOXES: N  PAID" or "UNPAID"
#
# Consolidation merges by: email > phone > normalized-name.
#
# 3 consolidated pairs (6 orders → 3 customers) + 22 singles = 28 orders, 25 customers.

JDS_PRODUCTS = [
    ("Chicken Breast 5kg", "1001001", 15.99),
    ("Turkey Burgers 4pk", "1001002", 12.49),
    ("Beef Patties 2kg",   "1001003", 18.99),
    ("Salmon Fillets 1kg", "1001004", 24.99),
    ("Veggie Nuggets 500g","1001005", 9.99),
]

def _jds_make_order(
    name: str,
    email: str | None,
    phone: str | None,
    order_id: int,
    items: list[tuple[int, int]],   # [(product_index, qty), ...]
    paid: bool,
) -> dict:
    """Build a JD Sweid order dict."""
    box_count = sum(qty for _, qty in items)
    return dict(
        name=name, email=email, phone=phone, order_id=order_id,
        items=items, paid=paid, box_count=box_count,
    )

def _generate_jds_orders() -> list[dict]:
    """Return 28 orders that consolidate to 25 customers totalling 99 boxes."""
    orders: list[dict] = []
    oid = 90001  # starting order-ID counter

    # ── Consolidated pair 1: email merge ──
    # "Alice Anderson" and "A. Anderson" share alice.anderson@example.com
    orders.append(_jds_make_order(
        "Alice Anderson", "alice.anderson@example.com", "905-555-0101", oid,
        [(0, 3), (1, 2)], True,    # 5 boxes
    ))
    oid += 1
    orders.append(_jds_make_order(
        "A. Anderson", "alice.anderson@example.com", None, oid,
        [(2, 1)], False,           # 1 box
    ))
    oid += 1

    # ── Consolidated pair 2: phone merge ──
    # "Bob Baker" and "Robert Baker" share phone 905-555-0102
    # One has an email so originalEmails is non-empty for this merged customer
    orders.append(_jds_make_order(
        "Bob Baker", "bob.baker@example.com", "905-555-0102", oid,
        [(3, 2)], True,            # 2 boxes
    ))
    oid += 1
    orders.append(_jds_make_order(
        "Robert Baker", None, "905-555-0102", oid,
        [(4, 3)], True,            # 3 boxes
    ))
    oid += 1

    # ── Consolidated pair 3: name merge (triggers warning for name-only match) ──
    # "Carol Carter" and "CAROL CARTER" — same email, no phone
    # Has email so originalEmails is non-empty, but triggers name-variation warning
    orders.append(_jds_make_order(
        "Carol Carter", "carol.carter@example.com", None, oid,
        [(0, 2)], False,           # 2 boxes
    ))
    oid += 1
    orders.append(_jds_make_order(
        "CAROL CARTER", "carol.carter@example.com", None, oid,
        [(1, 1)], True,            # 1 box
    ))
    oid += 1

    # Running total so far: 6 orders, 14 boxes
    # Need 22 more orders with 85 more boxes (99 - 14 = 85).

    # 22 single-order customers
    single_customers = [
        # (name, email, phone, product_index, qty, paid)
        ("David Davis",      "david.davis@example.com",      "905-555-0201", 0, 4, True),
        ("Eve Edwards",      "eve.edwards@example.com",      "905-555-0202", 1, 3, False),
        ("Frank Foster",     "frank.foster@example.com",     "905-555-0203", 2, 5, True),
        ("Grace Green",      "grace.green@example.com",      "905-555-0204", 3, 4, True),
        ("Hank Harris",      "hank.harris@example.com",      "905-555-0205", 4, 3, False),
        ("Iris Ingram",      "iris.ingram@example.com",      "905-555-0206", 0, 5, True),
        ("Jack Jensen",      "jack.jensen@example.com",      "905-555-0207", 1, 4, True),
        ("Karen King",       "karen.king@example.com",       "905-555-0208", 2, 3, False),
        ("Leo Lambert",      "leo.lambert@example.com",      "905-555-0209", 3, 5, True),
        ("Mia Mitchell",     "mia.mitchell@example.com",     "905-555-0210", 4, 4, True),
        ("Noah Nelson",      "noah.nelson@example.com",      "905-555-0211", 0, 3, False),
        ("Olivia Owen",      "olivia.owen@example.com",      "905-555-0212", 1, 5, True),
        ("Paul Parker",      "paul.parker@example.com",      "905-555-0213", 2, 4, True),
        ("Quinn Quinn",      "quinn.quinn@example.com",      "905-555-0214", 3, 3, False),
        ("Rita Ross",        "rita.ross@example.com",         "905-555-0215", 4, 4, True),
        ("Sam Stewart",      "sam.stewart@example.com",       "905-555-0216", 0, 5, True),
        ("Tara Turner",      "tara.turner@example.com",      "905-555-0217", 1, 4, False),
        ("Uma Underwood",    None,                            "905-555-0218", 2, 4, True),   # no email
        ("Victor Vance",     None,                            "905-555-0219", 3, 4, True),   # no email
        ("Wendy Walters",    None,                            "905-555-0220", 4, 3, False),  # no email
        ("Xavier Xu",        "xavier.xu@example.com",         None,           0, 3, True),   # no phone
        ("Yolanda Young",    "yolanda.young@example.com",     None,           1, 3, True),   # no phone
    ]

    # Verify box total: 14 (pairs) + sum of single qtys should == 99
    single_box_total = sum(qty for *_, qty, _ in single_customers)
    assert 14 + single_box_total == 99, f"Box total wrong: 14 + {single_box_total} = {14 + single_box_total}"
    assert len(single_customers) == 22

    for name, email, phone, pidx, qty, paid in single_customers:
        orders.append(_jds_make_order(name, email, phone, oid, [(pidx, qty)], paid))
        oid += 1

    assert len(orders) == 28
    total_boxes = sum(o["box_count"] for o in orders)
    assert total_boxes == 99, f"Total boxes: {total_boxes}"
    return orders


def _write_jds_supporter_block(pdf: FPDF, order: dict) -> None:
    """Write one SUPPORTER block in JD Sweid format."""
    lh = 5  # line height

    # "SUPPORTER  PRODUCTS ORDERED" header (what the parser splits on)
    pdf.set_font("Helvetica", "B", 10)
    pdf.cell(0, lh, "SUPPORTER  PRODUCTS ORDERED", new_x="LMARGIN", new_y="NEXT")

    pdf.set_font("Helvetica", "", 10)

    # Name
    pdf.cell(0, lh, order["name"], new_x="LMARGIN", new_y="NEXT")

    # Email (if present)
    if order["email"]:
        pdf.cell(0, lh, order["email"], new_x="LMARGIN", new_y="NEXT")

    # Phone (if present)
    if order["phone"]:
        pdf.cell(0, lh, order["phone"], new_x="LMARGIN", new_y="NEXT")

    # Order ID
    pdf.cell(0, lh, f"Order ID: {order['order_id']}", new_x="LMARGIN", new_y="NEXT")

    # Column headers (parser skips these)
    pdf.set_font("Helvetica", "B", 8)
    pdf.cell(0, lh, "QTY   UNIT PRICE   SUBTOTAL", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 10)

    # Product lines — Syncfusion format: "ProductName (SKU)" then qty on next line
    for pidx, qty in order["items"]:
        pname, sku, price = JDS_PRODUCTS[pidx]
        # Product + SKU line
        pdf.cell(0, lh, f"{pname} ({sku})", new_x="LMARGIN", new_y="NEXT")
        # Quantity line (standalone number — the Syncfusion two-line format)
        pdf.cell(0, lh, str(qty), new_x="LMARGIN", new_y="NEXT")
        # Price lines (the parser can optionally pick these up)
        subtotal = price * qty
        pdf.cell(0, lh, f"{price:.2f}", new_x="LMARGIN", new_y="NEXT")
        pdf.cell(0, lh, f"{subtotal:.2f}", new_x="LMARGIN", new_y="NEXT")

    # Box count + payment status
    status = "PAID" if order["paid"] else "UNPAID"
    pdf.cell(0, lh, f"# OF BOXES: {order['box_count']}  {status}", new_x="LMARGIN", new_y="NEXT")

    # Blank line separator
    pdf.cell(0, lh, "", new_x="LMARGIN", new_y="NEXT")


def generate_jdsweid_pdf(path: str) -> None:
    orders = _generate_jds_orders()

    pdf = FPDF()
    pdf.set_auto_page_break(auto=True, margin=15)
    pdf.add_page()

    # Document header
    pdf.set_font("Helvetica", "B", 14)
    pdf.cell(0, 8, "SUPPORTER ORDERS SUMMARY", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 10)
    pdf.cell(0, 6, "Delivery Date: 2026-03-15", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 6, "Location: Community Centre, 123 Maple St", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 6, "Time: 4:00 PM - 6:00 PM", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 8, "", new_x="LMARGIN", new_y="NEXT")

    for order in orders:
        # Check if we need a new page (leave room for at least one block)
        if pdf.get_y() > 230:
            pdf.add_page()
        _write_jds_supporter_block(pdf, order)

    # Summary section at the end (parser should stop here)
    pdf.cell(0, 8, "", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "B", 12)
    pdf.cell(0, 8, "PRODUCTS ORDERED SUMMARY", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 10)
    pdf.cell(0, 6, "TOTAL # OF ORDERS: 28", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 6, "CAMPAIGN TOTAL: $1,234.56", new_x="LMARGIN", new_y="NEXT")

    pdf.output(path)
    print(f"Generated {path}  ({len(orders)} orders)")


# ─── Little Caesars fixture ─────────────────────────────────────────────────
#
# Target: 35 orders, 97 total boxes.
#
# Format per order block (separated by form-feed \f):
#   Group Delivery
#   buyerName (Order #XXXXX, Seller Name: sellerName)
#   Phone #: XXX-XXX-XXXX
#   PRODUCT NAME   QTY   PRICE   SUBTOTAL
#   Product Name (SKU)
#   Price: $XX.XX  QTY  $SUBTOTAL  $TOTAL  YES/NO
#
# Sellers become customers. 12 sellers with 1-5 orders each (35 total).

LC_PRODUCTS = [
    ("Pepperoni Pizza Kit",       "PP",  10.99),
    ("Thin Crust Pizza Kit",      "TC",  10.99),
    ("Crazy Bread Kit",           "CB",   7.99),
    ("Cookie Dough Kit",          "CD",   9.99),
    ("Italian Cheese Bread Kit",  "ICB", 11.99),
]

LC_SELLERS = [
    # (seller_name, number_of_orders)
    ("Scout Alpha",    5),
    ("Scout Bravo",    4),
    ("Scout Charlie",  4),
    ("Scout Delta",    3),
    ("Scout Echo",     3),
    ("Scout Foxtrot",  3),
    ("Scout Golf",     3),
    ("Scout Hotel",    2),
    ("Scout India",    2),
    ("Scout Juliet",   2),
    ("Scout Kilo",     2),
    ("Scout Lima",     2),
]
assert sum(n for _, n in LC_SELLERS) == 35

# Buyer names (NATO + number)
LC_BUYERS = [
    "Alex Novak",     "Beth Owens",    "Carl Pratt",    "Dana Quinn",
    "Evan Reed",      "Faye Stone",    "Gary Tran",     "Holly Underhill",
    "Ivan Voss",      "Julia Wells",   "Kurt Xander",   "Laura Yates",
    "Mike Zeller",    "Nora Abbott",   "Oscar Byrne",   "Pam Crane",
    "Reid Drake",     "Sara Elliot",   "Troy Finch",    "Una Grant",
    "Vince Hardy",    "Wanda Irwin",   "Xena James",    "Yuri Kent",
    "Zara Long",      "Adam Marsh",    "Bree Nash",     "Cole Park",
    "Dawn Reese",     "Erik Shaw",     "Fern Tate",     "Glen Unger",
    "Hope Vega",      "Ira Walsh",     "Jade Yoder",
]
assert len(LC_BUYERS) == 35


def _generate_lc_orders() -> list[dict]:
    """Return 35 LC order dicts that total 97 boxes."""
    orders: list[dict] = []
    buyer_idx = 0
    oid = 50001

    # We need exact box totals. Pre-assign quantities to hit 97.
    # 35 orders × ~2.77 avg = 97 boxes.
    # Use a repeating pattern: quantities cycle through values that sum correctly.
    # 12×3 + 11×2 + 7×3 + 5×1 = 36+22+21+5 ... let me just list them.
    qtys = [
        3, 2, 3, 3, 2,   # Scout Alpha  (5 orders = 13 boxes)
        3, 3, 2, 3,       # Scout Bravo  (4 orders = 11 boxes)
        2, 3, 3, 2,       # Scout Charlie(4 orders = 10 boxes)
        3, 3, 2,          # Scout Delta  (3 orders = 8 boxes)
        3, 2, 3,          # Scout Echo   (3 orders = 8 boxes)
        2, 3, 3,          # Scout Foxtrot(3 orders = 8 boxes)
        3, 2, 2,          # Scout Golf   (3 orders = 7 boxes)
        3, 3,             # Scout Hotel  (2 orders = 6 boxes)
        3, 2,             # Scout India  (2 orders = 5 boxes)
        3, 3,             # Scout Juliet (2 orders = 6 boxes)
        2, 3,             # Scout Kilo   (2 orders = 5 boxes)
        3, 2,             # Scout Lima   (2 orders = 5 boxes)
    ]
    # Sum check
    running = sum(qtys)
    # Adjust last few to hit exactly 97
    diff = 97 - running
    # Apply diff to the last entry
    qtys[-1] += diff
    assert sum(qtys) == 97, f"LC box total: {sum(qtys)}"
    assert len(qtys) == 35

    qi = 0
    for seller_name, n_orders in LC_SELLERS:
        for _ in range(n_orders):
            buyer = LC_BUYERS[buyer_idx]
            qty = qtys[qi]

            # Pick product: cycle through
            pidx = qi % len(LC_PRODUCTS)
            pname, sku, price = LC_PRODUCTS[pidx]

            # ~3 orders without phone to trigger warnings
            has_phone = buyer_idx not in (7, 19, 30)
            phone = _phone("416", f"555", f"{1000 + buyer_idx:04d}") if has_phone else None

            paid = buyer_idx % 3 != 0  # ~2/3 paid

            orders.append(dict(
                seller=seller_name,
                buyer=buyer,
                order_id=oid,
                phone=phone,
                product_idx=pidx,
                product_name=pname,
                sku=sku,
                price=price,
                qty=qty,
                paid=paid,
            ))

            oid += 1
            buyer_idx += 1
            qi += 1

    assert len(orders) == 35
    assert sum(o["qty"] for o in orders) == 97
    return orders


def _write_lc_block(pdf: FPDF, order: dict) -> None:
    """Write one Little Caesars order block."""
    lh = 5

    pdf.set_font("Helvetica", "B", 11)
    pdf.cell(0, lh, "Group Delivery", new_x="LMARGIN", new_y="NEXT")

    pdf.set_font("Helvetica", "", 10)

    # Header: "buyerName (Order #XXXXX, Seller Name: sellerName)"
    header = f"{order['buyer']} (Order #{order['order_id']}, Seller Name: {order['seller']})"
    pdf.cell(0, lh, header, new_x="LMARGIN", new_y="NEXT")

    # Phone (buyer's phone)
    if order["phone"]:
        pdf.cell(0, lh, f"Phone #: {order['phone']}", new_x="LMARGIN", new_y="NEXT")

    # Column headers
    pdf.set_font("Helvetica", "B", 8)
    pdf.cell(0, lh, "PRODUCT NAME   QTY   PRICE   SUBTOTAL", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 10)

    # Product line: "Product Name (SKU)"
    pdf.cell(0, lh, f"{order['product_name']} ({order['sku']})", new_x="LMARGIN", new_y="NEXT")

    # Price line
    subtotal = order["price"] * order["qty"]
    price_line = f"Price: ${order['price']:.2f}  {order['qty']}  ${subtotal:.2f}  ${subtotal:.2f}"
    pdf.cell(0, lh, price_line, new_x="LMARGIN", new_y="NEXT")

    # Payment status on its own line (parser expects standalone YES/NO)
    yn = "YES" if order["paid"] else "NO"
    pdf.cell(0, lh, yn, new_x="LMARGIN", new_y="NEXT")

    # Spacer
    pdf.cell(0, lh, "", new_x="LMARGIN", new_y="NEXT")


def generate_little_caesars_pdf(path: str) -> None:
    orders = _generate_lc_orders()

    pdf = FPDF()
    pdf.set_auto_page_break(auto=True, margin=15)

    for order in orders:
        # Each order block on a new page (form-feed separated)
        pdf.add_page()
        _write_lc_block(pdf, order)

    pdf.output(path)
    print(f"Generated {path}  ({len(orders)} orders)")


# ─── Main ────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import os
    script_dir = os.path.dirname(os.path.abspath(__file__))

    generate_jdsweid_pdf(os.path.join(script_dir, "jdsweid.pdf"))
    generate_little_caesars_pdf(os.path.join(script_dir, "little_caesars.pdf"))

    print("\nDone. Run parser tests to verify:")
    print("  flutter test test/features/import/parsers/jd_sweid_parser_test.dart")
    print("  flutter test test/features/import/parsers/little_caesars_parser_test.dart")
