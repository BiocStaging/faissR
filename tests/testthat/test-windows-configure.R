test_that("Windows diagnostic Makevars do not pass unsupported flang flags", {
    configure <- test_path("../../configure.win")
    if (!file.exists(configure)) {
        skip("configure.win is unavailable in the installed-package context.")
    }
    if (!nzchar(Sys.which("sh"))) {
        skip("A POSIX shell is required for this source-tree configure test.")
    }
    configure_source <- readLines(configure, warn = FALSE)
    expect_false(any(grepl(
        "Wno-unused-command-line-argument",
        configure_source,
        fixed = TRUE
    )))

    root <- tempfile("faissR-configure-win-")
    dir.create(file.path(root, "src"), recursive = TRUE)
    file.copy(configure, file.path(root, "configure.win"))

    old <- setwd(root)
    on.exit(setwd(old), add = TRUE)
    status <- system2("sh", "configure.win", stdout = TRUE, stderr = TRUE)
    exit_status <- attr(status, "status")
    if (is.null(exit_status)) {
        exit_status <- 0L
    }
    expect_identical(exit_status, 0L)

    makevars <- readLines(file.path(root, "src", "Makevars.win"), warn = FALSE)
    expect_false(any(grepl("Wno-unused-command-line-argument", makevars, fixed = TRUE)))
    expect_false(any(grepl("^PKG_FFLAGS", makevars)))
    expect_true(any(grepl("FAISSR_WINDOWS_NO_FAISS", makevars, fixed = TRUE)))
})
