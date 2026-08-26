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
  expect_true(is.na(contract$canonical_reimplementation))
  expect_match(contract$implementation_label, "RAPIDS cuVS")
})
