test_that("style method aliases normalize without changing stable families", {
  expect_identical(faissR:::normalize_nn_method("nsg_style"), "nsg")
  expect_identical(faissR:::normalize_nn_method("vamana_style"), "vamana")
  expect_identical(faissR:::normalize_nn_method("nndescent_style"), "nndescent")

  for (alias in c("nsg", "vamana", "nndescent")) {
    expect_identical(faissR:::normalize_nn_method(alias), alias)
  }
})

test_that("package-owned style routes disclose noncanonical scope", {
  cases <- list(
    nsg_style = c("nsg", "cpu_nsg"),
    vamana_style = c("vamana", "cpu_vamana"),
    nndescent_style = c("nndescent", "cpu_nndescent")
  )

  for (alias in names(cases)) {
    contract <- faissR:::nn_method_implementation_contract(alias, cases[[alias]][[2L]])
    expect_identical(contract$method_family, cases[[alias]][[1L]])
    expect_identical(contract$preferred_public_method, alias)
    expect_identical(contract$implementation_scope, "package_owned_style_implementation")
    expect_identical(contract$implementation_status, "experimental")
    expect_true(contract$experimental)
    expect_identical(
      contract$principal_evidence_scope,
      "excluded_from_principal_performance_claims"
    )
    expect_false(contract$canonical_reimplementation)
  }
})

test_that("direct cuVS NN-descent is distinguished from package-owned style code", {
  contract <- faissR:::nn_method_implementation_contract(
    "nndescent_style",
    "cuda_cuvs_nndescent"
  )
  expect_identical(contract$preferred_public_method, "nndescent_style")
  expect_identical(contract$implementation_scope, "external_provider_implementation")
  expect_identical(contract$implementation_status, "external_provider")
  expect_false(contract$experimental)
  expect_true(is.na(contract$canonical_reimplementation))
  expect_match(contract$implementation_label, "RAPIDS cuVS")
})

test_that("capability metadata identifies experimental and provider routes", {
  caps <- nn_capabilities()
  expect_true("implementation_status" %in% names(caps))
  expect_true(all(
    caps$implementation_status[caps$method %in% c("nsg", "vamana")] ==
      "experimental"
  ))
  expect_identical(
    unique(caps$implementation_status[
      caps$method == "nndescent" & caps$backend == "cpu"
    ]),
    "experimental"
  )
  expect_identical(
    unique(caps$implementation_status[
      caps$method == "nndescent" & caps$backend == "cuda"
    ]),
    "external_provider"
  )
})

test_that("printing a package-owned style result exposes experimental status", {
  x <- structure(
    list(
      indices = matrix(c(2L, 1L), ncol = 1L),
      distances = matrix(c(1, 1), ncol = 1L),
      implementation_label = "faissR package-owned test refinement",
      implementation_scope = "package_owned_style_implementation",
      implementation_status = "experimental"
    ),
    class = c("faissR_nn", "list"),
    backend = "cpu_nsg",
    metric = "euclidean",
    exact = FALSE
  )
  expect_output(print(x), "status: experimental", fixed = TRUE)
  expect_output(print(x), "canonical reproduction: no", fixed = TRUE)
})
