"""Build an editable Word copy of the JSS supplementary material."""

from copy import deepcopy
from pathlib import Path
import re
import subprocess
import tempfile

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt

from docx_layout import apply_reading_layout, expand_latex_multicolumns


HERE = Path(__file__).resolve().parent
SOURCE = HERE / "faissR_jss_supplement.tex"
OUTPUT = HERE / "faissR_jss_supplement.docx"
REFERENCE = HERE / "faissR_jss.docx"


def _set_repeating_header(row) -> None:
    """Mark a Word table row as a repeating header."""
    properties = row.get_or_add_trPr()
    if properties.find(qn("w:tblHeader")) is None:
        repeat = OxmlElement("w:tblHeader")
        repeat.set(qn("w:val"), "true")
        properties.append(repeat)


def _clear_repeating_header(row) -> None:
    """Remove a copied repeating-header marker from a Word table row."""
    properties = row.get_or_add_trPr()
    for repeat in list(properties.findall(qn("w:tblHeader"))):
        properties.remove(repeat)


def split_comprehensive_dataset_panels(document) -> None:
    """Give each long comparison panel its own repeatable Word header."""
    target = None
    panel_starts = None
    for table in document.tables:
        starts = [
            index for index, row in enumerate(table.rows)
            if row.cells and row.cells[0].text.strip().startswith("Panel ")
        ]
        if len(starts) == 4:
            target = table
            panel_starts = starts
            break
    if target is None or panel_starts is None:
        raise ValueError("Could not identify the four comparison panels")

    source_table = target._tbl
    source_rows = list(source_table.tr_lst)
    boundaries = panel_starts + [len(source_rows)]
    replacement_tables = []
    for start, end in zip(boundaries, boundaries[1:]):
        panel_table = deepcopy(source_table)
        for row in list(panel_table.tr_lst):
            panel_table.remove(row)
        for row in source_rows[start:end]:
            panel_table.append(deepcopy(row))
        for row in panel_table.tr_lst:
            _clear_repeating_header(row)
        for row in panel_table.tr_lst[:2]:
            _set_repeating_header(row)
        replacement_tables.append(panel_table)

    for index, panel_table in enumerate(replacement_tables):
        source_table.addprevious(panel_table)
        if index < len(replacement_tables) - 1:
            spacer = OxmlElement("w:p")
            source_table.addprevious(spacer)
    source_table.getparent().remove(source_table)


def merge_multicolumn_headers(document) -> None:
    """Restore header spans that were expanded for Pandoc's table reader."""
    for table in document.tables:
        if not table.rows:
            continue
        first = tuple(cell.text.strip() for cell in table.rows[0].cells)
        if first == ("", "BiocNeighbors", "", "", "RcppHNSW", "", ""):
            table.cell(0, 1).merge(table.cell(0, 3))
            table.cell(0, 4).merge(table.cell(0, 6))
            for index in (1, 4):
                table.cell(0, index).paragraphs[0].alignment = (
                    WD_ALIGN_PARAGRAPH.CENTER
                )
            for row in table.rows[1:]:
                for cell in row.cells[1:]:
                    cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
        elif first == (
            "", "Experimental installed policy", "", "",
            "Post hoc sensitivity", "", "",
        ):
            table.cell(0, 1).merge(table.cell(0, 3))
            table.cell(0, 4).merge(table.cell(0, 6))
            for index in (1, 4):
                table.cell(0, index).paragraphs[0].alignment = (
                    WD_ALIGN_PARAGRAPH.CENTER
                )
        elif first[0].startswith("Panel ") and all(
            not value for value in first[1:]
        ):
            table.cell(0, 0).merge(table.cell(0, len(first) - 1))
            table.cell(0, 0).paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.LEFT
            second = tuple(cell.text.strip() for cell in table.rows[1].cells)
            if second == (
                "Dataset", "BiocNeighbors HNSW", "", "RcppHNSW HNSW", "",
            ):
                table.cell(1, 1).merge(table.cell(1, 2))
                table.cell(1, 3).merge(table.cell(1, 4))
            elif second == (
                "Dataset", "BiocNeighbors Annoy / faissR auto", "",
                "RcppAnnoy / faissR auto", "",
            ):
                table.cell(1, 1).merge(table.cell(1, 2))
                table.cell(1, 3).merge(table.cell(1, 4))
            elif second[0] == "Dataset" and second[1].startswith("rnndescent"):
                table.cell(1, 1).merge(table.cell(1, 4))


def word_source(source: str) -> str:
    """Normalize LaTeX constructs that Pandoc does not map cleanly to Word."""
    source = re.sub(
        r"\\shortstack(?:\[[^]]*\])?\{([^{}]*)\}",
        lambda match: match.group(1).replace(r"\\", " "),
        source,
    )
    source = re.sub(r"\\cmidrule(?:\([^)]*\))?\{[^}]*\}", "", source)
    source = source.replace(r"\paragraph{", r"\paragraph*{")
    for label, number in re.findall(
        r"\\newlabel\{([^}]+)\}\{\{([^}]+)\}",
        SOURCE.with_suffix(".aux").read_text(),
    ):
        source = source.replace(f"\\ref{{{label}}}", number)
    if re.search(r"\\ref\{", source):
        raise ValueError("Unresolved cross-reference; rebuild the PDF first")
    source = re.sub(
        r"\\path\{([^{}]+)\}",
        lambda match: r"\texttt{" + match.group(1).replace("_", r"\_") + "}",
        source,
    )
    source = source.replace(r"\textsuperscript{\(\dagger\)}", " ")
    source = source.replace(r"\dagger", "")
    source = source.replace(r"\ast", "")
    source = expand_latex_multicolumns(source)
    source = re.sub(r"\$\^\{([^}]+)\}\$", r" (\1)", source)
    source = source.replace(r"\newcolumntype{Y}{>{\raggedright\arraybackslash}X}", "")
    source = source.replace(
        r"\newcolumntype{P}[1]{>{\raggedright\arraybackslash}p{#1}}",
        "",
    )
    source = source.replace(
        r"\begin{tabularx}{\linewidth}{p{0.27\linewidth}Y}",
        r"\begin{tabular}{p{0.27\linewidth}p{0.63\linewidth}}",
    )
    source = source.replace(
        r"\begin{tabularx}{\textwidth}{@{}>{\raggedright\arraybackslash}p{0.42\textwidth}Y@{}}",
        r"\begin{tabular}{p{0.42\textwidth}p{0.48\textwidth}}",
    )
    source = source.replace(
        r"\begin{tabularx}{\textwidth}{@{}p{0.13\textwidth}p{0.23\textwidth}X p{0.09\textwidth}@{}}",
        r"\begin{tabular}{p{0.13\textwidth}p{0.23\textwidth}p{0.45\textwidth}p{0.09\textwidth}}",
    )
    source = source.replace(
        r"\begin{tabularx}{\textwidth}{@{}p{0.19\textwidth}p{0.25\textwidth}X@{}}",
        r"\begin{tabular}{p{0.19\textwidth}p{0.25\textwidth}p{0.46\textwidth}}",
    )
    source = source.replace(
        r"\begin{tabularx}{\textwidth}{@{}>{\raggedright\arraybackslash}p{0.19\textwidth}>{\raggedright\arraybackslash}p{0.43\textwidth}X@{}}",
        r"\begin{tabular}{p{0.19\textwidth}p{0.43\textwidth}p{0.28\textwidth}}",
    )
    source = source.replace(
        r"\begin{tabularx}{\linewidth}{P{0.30\linewidth}Y}",
        r"\begin{tabular}{p{0.30\linewidth}p{0.60\linewidth}}",
    )
    source = source.replace(
        "\\begin{tabularx}{\\linewidth}{P{0.19\\linewidth}"
        "P{0.24\\linewidth}Y\nP{0.13\\linewidth}}",
        "\\begin{tabular}{p{0.19\\linewidth}p{0.24\\linewidth}"
        "p{0.31\\linewidth}p{0.13\\linewidth}}",
    )
    source = source.replace(
        r"\begin{tabularx}{\linewidth}{lrrY}",
        r"\begin{tabular}{lrrp{0.55\linewidth}}",
    )
    source = source.replace(
        r"\begin{tabularx}{\linewidth}{p{0.32\linewidth}p{0.18\linewidth}Y}",
        r"\begin{tabular}{p{0.32\linewidth}p{0.18\linewidth}p{0.40\linewidth}}",
    )
    source = source.replace(
        r"\begin{tabularx}{\linewidth}{p{0.25\linewidth}Y}",
        r"\begin{tabular}{p{0.25\linewidth}p{0.65\linewidth}}",
    )
    source = source.replace(
        r"\begin{tabularx}{\linewidth}{P{0.25\linewidth}Y}",
        r"\begin{tabular}{p{0.25\linewidth}p{0.65\linewidth}}",
    )
    source = source.replace(
        r"\begin{tabularx}{\linewidth}{P{0.32\linewidth}P{0.18\linewidth}Y}",
        r"\begin{tabular}{p{0.32\linewidth}p{0.18\linewidth}p{0.40\linewidth}}",
    )
    source = source.replace(
        r"\begin{tabularx}{\textwidth}{@{}lY@{}}",
        r"\begin{tabular}{@{}lp{0.72\textwidth}@{}}",
    )
    source = source.replace(
        r"\begin{tabularx}{\textwidth}{@{}lYY@{}}",
        r"\begin{tabular}{@{}lp{0.36\textwidth}p{0.36\textwidth}@{}}",
    )
    source = source.replace(
        r"\begin{tabularx}{\textwidth}{@{}YY@{}}",
        r"\begin{tabular}{@{}p{0.45\textwidth}p{0.45\textwidth}@{}}",
    )
    source = source.replace(
        r"\begin{tabularx}{\textwidth}{@{}Yrr@{}}",
        r"\begin{tabular}{@{}p{0.62\textwidth}rr@{}}",
    )
    source = source.replace(
        r"\begin{tabularx}{\textwidth}{@{}Xrr@{}}",
        r"\begin{tabular}{@{}p{0.62\textwidth}rr@{}}",
    )
    source = source.replace(
        r"\begin{tabularx}{\textwidth}{@{}Xrrrr@{}}",
        r"\begin{tabular}{@{}p{0.42\textwidth}rrrr@{}}",
    )
    source = source.replace(
        r"\begin{tabularx}{\textwidth}{@{}Xlrrr@{}}",
        r"\begin{tabular}{@{}p{0.34\textwidth}lrrr@{}}",
    )
    source = source.replace(
        r"\begin{tabularx}{\textwidth}{@{}l*{4}{>{\centering\arraybackslash}X}@{}}",
        r"\begin{tabular}{@{}p{0.18\textwidth}p{0.18\textwidth}p{0.18\textwidth}p{0.18\textwidth}p{0.18\textwidth}@{}}",
    )
    source = source.replace(
        r"\begin{tabularx}{\textwidth}{@{}l@{\hspace{1.2em}}*{5}{>{\centering\arraybackslash}X}@{}}",
        r"\begin{tabular}{@{}p{0.14\textwidth}p{0.15\textwidth}p{0.15\textwidth}p{0.15\textwidth}p{0.15\textwidth}p{0.15\textwidth}@{}}",
    )
    source = source.replace(
        r"\begin{longtable}{P{0.22\linewidth}P{0.31\linewidth}P{0.37\linewidth}}",
        r"\begin{longtable}{p{0.22\linewidth}p{0.31\linewidth}p{0.37\linewidth}}",
    )
    source = source.replace(
        r"\begin{longtable}{P{0.18\linewidth}P{0.75\linewidth}}",
        r"\begin{longtable}{p{0.18\linewidth}p{0.75\linewidth}}",
    )
    source = source.replace(
        r"\begin{longtable}{P{0.20\linewidth}P{0.72\linewidth}}",
        r"\begin{longtable}{p{0.20\linewidth}p{0.72\linewidth}}",
    )
    source = source.replace(r"\end{tabularx}", r"\end{tabular}")
    source = re.sub(
        r"\\endfirsthead.*?\\endhead",
        "",
        source,
        flags=re.DOTALL,
    )
    return source


def polish(path: Path) -> None:
    document = Document(path)
    table_captions = [
        paragraph for paragraph in document.paragraphs
        if paragraph.style.name == "Table Caption"
    ]
    for current, following in zip(table_captions, table_captions[1:]):
        if current.text.strip() == following.text.strip():
            current._element.getparent().remove(current._element)
    for section in document.sections:
        section.header_distance = Pt(35.4)
        section.footer_distance = Pt(35.4)
    for shape in document.inline_shapes:
        if shape.height > Inches(3.5):
            scale = Inches(3.5) / shape.height
            shape.width = int(shape.width * scale)
            shape.height = Inches(3.5)
    for paragraph in document.paragraphs:
        text = paragraph.text.strip()
        if paragraph.style.name in {"First Paragraph", "Body Text"} and (
            text.startswith("(1) Bioinformatics Unit")
            or text.startswith("Moussa Kassim and Martin Ocharo")
        ):
            paragraph.alignment = WD_ALIGN_PARAGRAPH.LEFT
            paragraph.paragraph_format.line_spacing = 1.0
            paragraph.paragraph_format.space_after = Pt(4)
        if text == "Purpose and evidence boundary":
            paragraph.paragraph_format.page_break_before = True
        if text.startswith("Approximate method"):
            paragraph.paragraph_format.page_break_before = True
            paragraph.paragraph_format.space_before = Pt(42)
        if text.startswith("The datasets are COIL20"):
            page_break = paragraph.insert_paragraph_before()
            page_break.add_run().add_break(WD_BREAK.PAGE)
        if text.startswith(("CPU IVF", "CUDA IVF")):
            paragraph.alignment = WD_ALIGN_PARAGRAPH.LEFT
        if (
            "auto_policy_status=" in text
            or "hardware_extrapolated_unvalidated" in text
        ):
            paragraph.alignment = WD_ALIGN_PARAGRAPH.LEFT
    for table in document.tables:
        if not table.rows:
            continue
        while table.rows and all(
            not cell.text.strip() for cell in table.rows[0].cells
        ):
            table._tbl.remove(table.rows[0]._tr)
        if not table.rows:
            continue
        headers = tuple(cell.text.strip() for cell in table.rows[0].cells)
        compact = headers == ("Backend/method", "Metric", "Recall at 15")
        wide_compact = headers == (
            "Comparator", "Class", "Pairs", "Both successful", "Matched",
            "Timeout", "Median [IQR]",
        )
        table.autofit = False
        header_properties = table.rows[0]._tr.get_or_add_trPr()
        if header_properties.find(qn("w:tblHeader")) is None:
            repeat = OxmlElement("w:tblHeader")
            repeat.set(qn("w:val"), "true")
            header_properties.append(repeat)
        for row in table.rows:
            row_properties = row._tr.get_or_add_trPr()
            if row_properties.find(qn("w:cantSplit")) is None:
                cant_split = OxmlElement("w:cantSplit")
                cant_split.set(qn("w:val"), "true")
                row_properties.append(cant_split)
            for cell in row.cells:
                tc_pr = cell._tc.get_or_add_tcPr()
                margins = tc_pr.find(qn("w:tcMar"))
                if margins is None:
                    margins = OxmlElement("w:tcMar")
                    tc_pr.append(margins)
                vertical_margin = 25 if compact else (40 if wide_compact else 80)
                for side, value in (
                    ("top", vertical_margin),
                    ("bottom", vertical_margin),
                    ("start", 120),
                    ("end", 120),
                ):
                    node = margins.find(qn(f"w:{side}"))
                    if node is None:
                        node = OxmlElement(f"w:{side}")
                        margins.append(node)
                    node.set(qn("w:w"), str(value))
                    node.set(qn("w:type"), "dxa")
                if compact or wide_compact:
                    for paragraph in cell.paragraphs:
                        paragraph.paragraph_format.space_before = Pt(0)
                        paragraph.paragraph_format.space_after = Pt(0)
                        paragraph.paragraph_format.line_spacing = 1.0
                        for run in paragraph.runs:
                            run.font.size = Pt(8.5)
        table_widths = {
            ("Component", "Configuration"): [2400, 6960],
            ("Method", "Tuned quantities"): [2500, 6860],
            ("Method", "Candidate values or construction rule"): [3600, 5760],
            ("Evidence", "Passing or completed", "Total"):
                [5600, 2160, 1600],
            ("Function", "Role"): [2500, 6860],
            ("Method", "CPU route", "CUDA route"): [1600, 3380, 4380],
            ("Dataset", "Rows", "Columns"): [4000, 2680, 2680],
            (
                "Dataset",
                "Source/release",
                "Representation searched",
                "Terms",
            ): [1800, 2200, 4060, 1300],
            (
                "Backend",
                "Contract pass",
                "Unsupported",
                "Target 0.99 pass",
                "Edge-case pass",
            ): [1450, 1900, 1550, 2100, 2360],
            ("Backend/method", "Metric", "Recall at 15"): [3500, 3000, 2860],
            ("Method", "Candidate settings"): [1900, 7460],
            ("Package", "Public interface and timing interpretation"):
                [1900, 7460],
            ("Requested names", "Publication treatment"): [2500, 6860],
            ("Backend", "Rows", "Datasets", "Covered contrasts"):
                [1200, 900, 1200, 6060],
            ("Evidence stream", "Status", "Required action"): [3000, 1800, 4560],
            (
                "Comparator", "Class", "Pairs", "Both OK", "Matched",
                "Timeout", "Median [IQR]",
            ): [1900, 1050, 850, 900, 900, 900, 2850],
            ("Comparison", "Datasets", "Median", "IQR", "Range"):
                [3900, 1100, 1200, 1580, 1580],
            (
                "Dataset", "FNN exact", "RANN exact", "Rnanoflann exact",
                "BiocNeighbors exact",
            ): [1680, 1920, 1920, 1920, 1920],
            (
                "Dataset", "BiocNeighbors HNSW", "RcppHNSW HNSW",
                "BiocNeighbors Annoy", "RcppAnnoy Annoy", "rnndescent",
            ): [1260, 1620, 1620, 1620, 1620, 1620],
        }
        widths = table_widths.get(headers)
        if widths is not None:
            table_properties = table._tbl.tblPr
            layout = table_properties.find(qn("w:tblLayout"))
            if layout is None:
                layout = OxmlElement("w:tblLayout")
                table_properties.append(layout)
            layout.set(qn("w:type"), "fixed")
            table_width = table_properties.find(qn("w:tblW"))
            table_width.set(qn("w:type"), "dxa")
            table_width.set(qn("w:w"), str(sum(widths)))
            table_grid = table._tbl.tblGrid
            for grid_column in list(table_grid):
                table_grid.remove(grid_column)
            for width in widths:
                grid_column = OxmlElement("w:gridCol")
                grid_column.set(qn("w:w"), str(width))
                table_grid.append(grid_column)
            for row in table.rows:
                for cell, width in zip(row.cells, widths):
                    cell_properties = cell._tc.get_or_add_tcPr()
                    cell_width = cell_properties.find(qn("w:tcW"))
                    if cell_width is None:
                        cell_width = OxmlElement("w:tcW")
                        cell_properties.append(cell_width)
                    cell_width.set(qn("w:type"), "dxa")
                    cell_width.set(qn("w:w"), str(width))
    apply_reading_layout(document, SOURCE.read_text(), supplementary=True)
    split_comprehensive_dataset_panels(document)
    merge_multicolumn_headers(document)
    document.save(path)


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="faissR-jss-supplement-") as tmp:
        temporary_dir = Path(tmp)
        source = temporary_dir / "supplement.tex"
        source_text = word_source(SOURCE.read_text(encoding="utf-8"))
        for figure in (
            "fig_paired_cpu_log_ratio.pdf",
            "fig_comprehensive_r_log_ratio.pdf",
        ):
            source_figure = HERE / figure
            if source_figure.exists():
                output_base = temporary_dir / source_figure.stem
                subprocess.run(
                    ["pdftoppm", "-png", "-singlefile", "-r", "180",
                     str(source_figure), str(output_base)],
                    check=True,
                )
                source_text = source_text.replace(figure, f"{source_figure.stem}.png")
        source.write_text(source_text, encoding="utf-8")
        intermediate = temporary_dir / "supplement.docx"
        command = [
            "pandoc",
            str(source),
            "--from=latex",
            "--to=docx",
            "--standalone",
            "--number-sections",
            "--citeproc",
            "--metadata=reference-section-title:References",
            f"--bibliography={HERE / 'faissR_jss.bib'}",
            f"--output={intermediate}",
        ]
        if REFERENCE.exists():
            command.append(f"--reference-doc={REFERENCE}")
        subprocess.run(command, check=True, cwd=temporary_dir)
        OUTPUT.write_bytes(intermediate.read_bytes())
    polish(OUTPUT)


if __name__ == "__main__":
    main()
