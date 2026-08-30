test_that("metric preflight reports cosine and correlation edge rows", {
  x <- rbind(c(0, 0), c(1, 1), c(1, 2))

  cosine_cpu <- nn_metric_preflight(x, metric = "cosine", backend = "cpu")
  expect_identical(cosine_cpu$data_rows, 1L)
  expect_true(cosine_cpu$would_succeed)
  expect_identical(cosine_cpu$action, "cpu_zero_normalized_convention")

  cosine_cuda <- nn_metric_preflight(x, metric = "cosine", backend = "cuda")
  expect_false(cosine_cuda$would_succeed)
  expect_identical(cosine_cuda$action, "error_degenerate_cuda")

  correlation <- nn_metric_preflight(
    x,
    metric = "correlation",
    backend = "cpu"
  )
  expect_identical(correlation$data_rows, c(1L, 2L))
  expect_identical(correlation$degenerate_kind, "constant_row")
})

test_that("metric preflight reports query and non-finite rows separately", {
  data <- rbind(c(1, 0), c(0, 1))
  points <- rbind(c(0, 0), c(NA_real_, 1))
  out <- nn_metric_preflight(
    data,
    points,
    metric = "cosine",
    backend = "cpu"
  )
  expect_length(out$data_rows, 0L)
  expect_identical(out$points_rows, 1L)
  expect_identical(out$points_non_finite_rows, 2L)
  expect_false(out$would_succeed)
  expect_identical(out$action, "error_non_finite_all_backends")
})

test_that("metric preflight validates dimensions and auto ambiguity", {
  expect_error(
    nn_metric_preflight(matrix(1:4, 2), matrix(1:6, 2)),
    "same number of columns"
  )
  out <- nn_metric_preflight(
    matrix(0, 2, 2),
    metric = "cosine",
    backend = "auto"
  )
  expect_true(is.na(out$would_succeed))
  expect_match(out$action, "backend_dependent")
})
