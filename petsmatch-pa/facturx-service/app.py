"""Micro-service d'assemblage Factur-X (PDF/A-3 + XML CII embarqué).

Voir README.md. Le XML CII est produit par le service Node petsmatch-pa ;
ici on ne fait que l'emballage PDF/A-3, via la librairie de référence `factur-x`.
"""
from __future__ import annotations

import io
import xml.etree.ElementTree as ET

from flask import Flask, request, Response, jsonify
from facturx import generate_from_binary
from fpdf import FPDF

app = Flask(__name__)

RAM = "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100"
RSM = "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100"
UDT = "urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100"
NS = {"rsm": RSM, "ram": RAM, "udt": UDT}

VALID_LEVELS = {"minimum", "basicwl", "basic", "en16931", "extended"}


def _text(root: ET.Element, path: str) -> str:
    el = root.find(path, NS)
    return el.text.strip() if el is not None and el.text else ""


def render_fallback_pdf(xml_bytes: bytes) -> bytes:
    """PDF lisible minimal à partir du XML, quand aucun PDF source n'est fourni."""
    try:
        root = ET.fromstring(xml_bytes)
    except ET.ParseError:
        root = ET.Element("empty")

    number = _text(root, ".//rsm:ExchangedDocument/ram:ID")
    type_code = _text(root, ".//rsm:ExchangedDocument/ram:TypeCode")
    issue = _text(root, ".//rsm:ExchangedDocument/ram:IssueDateTime/udt:DateTimeString")
    seller = _text(root, ".//ram:SellerTradeParty/ram:Name")
    buyer = _text(root, ".//ram:BuyerTradeParty/ram:Name")
    summ = ".//ram:SpecifiedTradeSettlementHeaderMonetarySummation"
    ht = _text(root, f"{summ}/ram:TaxBasisTotalAmount")
    tva = _text(root, f"{summ}/ram:TaxTotalAmount")
    ttc = _text(root, f"{summ}/ram:GrandTotalAmount")
    due = _text(root, f"{summ}/ram:DuePayableAmount")
    currency = _text(root, ".//ram:InvoiceCurrencyCode") or "EUR"
    issue_fmt = f"{issue[6:8]}/{issue[4:6]}/{issue[0:4]}" if len(issue) == 8 else issue

    title = "FACTURE D'AVOIR" if type_code == "381" else "FACTURE"

    pdf = FPDF(unit="pt", format="A4")
    pdf.set_auto_page_break(auto=True, margin=40)
    pdf.add_page()
    pdf.set_font("Helvetica", "B", 16)
    pdf.set_text_color(12, 92, 108)
    pdf.cell(0, 22, seller or "-", ln=1)
    pdf.set_font("Helvetica", "B", 18)
    pdf.set_text_color(20, 20, 20)
    pdf.cell(0, 26, f"{title}  N° {number}", ln=1)
    pdf.set_font("Helvetica", "", 10)
    pdf.set_text_color(90, 90, 90)
    pdf.cell(0, 16, f"Date : {issue_fmt}", ln=1)
    if buyer:
        pdf.cell(0, 16, f"Destinataire : {buyer}", ln=1)
    pdf.ln(10)
    pdf.set_text_color(20, 20, 20)
    for label, value in (("Total HT", ht), ("TVA", tva), ("Total TTC", ttc), ("Reste a payer", due)):
        if value:
            pdf.set_font("Helvetica", "B" if label == "Total TTC" else "", 11)
            pdf.cell(120, 16, label)
            pdf.cell(0, 16, f"{value} {currency}", ln=1)
    pdf.ln(16)
    pdf.set_font("Helvetica", "", 8)
    pdf.set_text_color(120, 120, 120)
    pdf.multi_cell(
        0, 11,
        "Representation lisible generee automatiquement. Les donnees faisant foi sont "
        "celles du fichier factur-x.xml embarque dans ce PDF/A-3.",
    )
    return bytes(pdf.output())


@app.get("/health")
def health():
    return jsonify(ok=True)


@app.post("/facturx")
def facturx():
    xml_file = request.files.get("xml")
    if xml_file is None:
        return jsonify(error="champ 'xml' manquant"), 400
    xml_bytes = xml_file.read()

    level = (request.form.get("level") or "en16931").lower()
    if level not in VALID_LEVELS:
        return jsonify(error=f"level invalide : {level}"), 400

    pdf_file = request.files.get("pdf")
    pdf_bytes = pdf_file.read() if pdf_file is not None else render_fallback_pdf(xml_bytes)

    try:
        out = generate_from_binary(
            pdf_bytes,
            xml_bytes,
            flavor="factur-x",
            level=level,
            check_xsd=True,
            afrelationship="data",
        )
    except Exception as exc:  # noqa: BLE001 — on renvoie l'erreur lisible au client
        return jsonify(error=f"assemblage Factur-X : {exc}"), 422

    return Response(
        out,
        mimetype="application/pdf",
        headers={
            "X-Facturx-Level": level,
            "Content-Disposition": 'inline; filename="facture.pdf"',
        },
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8081)
