test_that("strict FAISS mode rejects a diagnostic WebAssembly build", {
    configure <- test_path("../../configure")
    if (!file.exists(configure)) {
        skip("configure is unavailable in the installed-package context.")
    }
    if (!nzchar(Sys.which("sh"))) {
        skip("A POSIX shell is required for this source-tree configure test.")
    }

    root <- tempfile("faissR-configure-unix-")
    dir.create(root)
    file.copy(configure, file.path(root, "configure"))

    old <- setwd(root)
    on.exit(setwd(old), add = TRUE)
    output <- suppressWarnings(system2(
        "sh",
        c("configure", "--host=wasm32-unknown-emscripten"),
        stdout = TRUE,
        stderr = TRUE,
        env = "FAISSR_REQUIRE_FAISS=1"
    ))

    expect_equal(attr(output, "status"), 1L)
    expect_true(any(grepl(
        "FAISSR_REQUIRE_FAISS=1, but FAISS is unavailable",
        output,
        fixed = TRUE
    )))
})

test_that("Unix FAISS builds link R numerical and Fortran libraries", {
    configure <- test_path("../../configure")
    if (!file.exists(configure)) {
        skip("configure is unavailable in the installed-package context.")
    }

    configure_source <- readLines(configure, warn = FALSE)
    configure_text <- paste(configure_source, collapse = "\n")

    expect_true(grepl(
        "LAPACK_LIBS.*BLAS_LIBS.*FLIBS",
        configure_text
    ))
})
