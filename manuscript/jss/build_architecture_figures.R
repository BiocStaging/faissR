#!/usr/bin/env Rscript

box <- function(x, y, w, h, label, fill, border = "#334155",
                cex = 0.78) {
  rect(x - w / 2, y - h / 2, x + w / 2, y + h / 2,
       col = fill, border = border, lwd = 1.1)
  text(x, y, label, cex = cex, col = "#172033")
}

arrow <- function(x0, y0, x1, y1, label = NULL) {
  arrows(x0, y0, x1, y1, length = 0.075, lwd = 1.1,
         col = "#52606D")
  if (!is.null(label)) text((x0 + x1) / 2, (y0 + y1) / 2 + 0.035,
                            label, cex = 0.62, col = "#52606D")
}

pdf("fig_architecture.pdf", width = 7.2, height = 4.0,
    family = "Helvetica", useDingbats = FALSE)
par(mar = rep(0.15, 4), xaxs = "i", yaxs = "i")
plot.new(); plot.window(c(0, 1), c(0, 1))
box(0.10, 0.76, 0.16, 0.18, "R double matrix\nor float matrix", "#DCEAF7")
box(0.32, 0.76, 0.18, 0.18, "Metric preflight\nnormalization\nlayout conversion", "#E8F1F8")
box(0.55, 0.76, 0.18, 0.18, "Capability and\nprovider dispatch", "#E7F3EC")
box(0.80, 0.76, 0.25, 0.18, "FAISS CPU / FAISS GPU\ncuVS / package-owned route", "#E7F3EC")
arrow(0.18, 0.76, 0.23, 0.76); arrow(0.41, 0.76, 0.46, 0.76)
arrow(0.64, 0.76, 0.675, 0.76)
box(0.40, 0.43, 0.22, 0.16, "Index construction\nor fitted-index reuse", "#FFF1D6")
box(0.68, 0.43, 0.18, 0.16, "Batched query\nand result ordering", "#FFF1D6")
arrow(0.76, 0.67, 0.46, 0.51); arrow(0.51, 0.43, 0.59, 0.43)
box(0.31, 0.13, 0.23, 0.16, "Host faissR_nn\nindices + distances\nroute metadata", "#DCEAF7")
box(0.72, 0.13, 0.25, 0.16, "Owning faissR_gpu_knn\ndevice-buffer views\nresidency metadata", "#EADFF4")
arrow(0.64, 0.35, 0.36, 0.21, "nn()")
arrow(0.71, 0.35, 0.72, 0.21, "nn_gpu()")
text(0.31, 0.025, "R analysis, prediction, graph construction", cex = 0.66,
     col = "#52606D")
text(0.72, 0.025, "compiled CUDA consumer or explicit host copy", cex = 0.66,
     col = "#52606D")
dev.off()

pdf("fig_selector_flow.pdf", width = 7.2, height = 5.0,
    family = "Helvetica", useDingbats = FALSE)
par(mar = rep(0.15, 4), xaxs = "i", yaxs = "i")
plot.new(); plot.window(c(0, 1), c(0, 1))
box(0.50, 0.94, 0.30, 0.09, "nn(data, backend, method, tuning)", "#DCEAF7")
box(0.50, 0.82, 0.42, 0.10, "Resolve backend\nexplicit argument or auto/session/CPU precedence", "#E8F1F8", cex = 0.67)
arrow(0.50, 0.895, 0.50, 0.865)
box(0.50, 0.69, 0.36, 0.09, "Check runtime capability and metric/input contract", "#E8F1F8", cex = 0.65)
arrow(0.50, 0.77, 0.50, 0.735)
box(0.25, 0.56, 0.32, 0.10, "Explicit method\nresolve its concrete provider", "#E7F3EC")
box(0.75, 0.56, 0.32, 0.10, "method = auto\nlookup experimental method policy", "#FFF1D6")
arrow(0.43, 0.655, 0.30, 0.61, "explicit")
arrow(0.57, 0.655, 0.70, 0.61, "auto")
box(0.25, 0.40, 0.34, 0.10, "tuning explicit: validate parameters\ntuning auto: within-method lookup", "#E7F3EC", cex = 0.70)
box(0.75, 0.40, 0.34, 0.10, "shape / metric / k / tier lookup\nrecord target and hardware extrapolation", "#FFF1D6", cex = 0.70)
arrow(0.25, 0.51, 0.25, 0.45); arrow(0.75, 0.51, 0.75, 0.45)
box(0.50, 0.24, 0.40, 0.10, "Dispatch resolved provider and parameters\n(no fallback after execution failure)", "#EADFF4")
arrow(0.25, 0.35, 0.43, 0.29); arrow(0.75, 0.35, 0.57, 0.29)
box(0.25, 0.08, 0.34, 0.10, "Return result + requested/resolved route\ntarget and extrapolation metadata", "#DCEAF7")
box(0.75, 0.08, 0.34, 0.10, "Explicit error\nunsupported combination or\nmissing required provider", "#F9DEDE")
arrow(0.44, 0.19, 0.31, 0.13, "supported")
arrow(0.56, 0.19, 0.69, 0.13, "unsupported")
dev.off()
