# Shared recall inference for publication benchmarks.

recall_script_seed <- function(seed) {
  value <- suppressWarnings(as.integer(seed[[1L]]))
  if (!is.finite(value)) value <- 1L
  as.integer(value %% .Machine$integer.max)
}

with_local_seed <- function(seed, code) {
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (had_seed) old_seed <- get(".Random.seed", envir = .GlobalEnv)
  on.exit({
    if (had_seed) {
      assign(".Random.seed", old_seed, envir = .GlobalEnv)
    } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      rm(".Random.seed", envir = .GlobalEnv)
    }
  }, add = TRUE)
  set.seed(recall_script_seed(seed))
  force(code)
}

query_bootstrap_lcb <- function(query_recall, confidence = 0.95,
                                resamples = 1000L, seed = 1L) {
  values <- as.numeric(query_recall)
  values <- values[is.finite(values)]
  if (!length(values)) return(NA_real_)
  if (length(values) == 1L || length(unique(values)) == 1L) return(mean(values))
  resamples <- as.integer(resamples)
  if (!is.finite(resamples) || resamples < 200L) {
    stop("`resamples` must be at least 200.", call. = FALSE)
  }
  alpha <- 1 - as.numeric(confidence)
  if (!is.finite(alpha) || alpha <= 0 || alpha >= 0.5) {
    stop("`confidence` must lie between 0.5 and 1.", call. = FALSE)
  }
  means <- with_local_seed(seed, replicate(
    resamples, mean(sample(values, length(values), replace = TRUE))
  ))
  unname(stats::quantile(means, probs = alpha, names = FALSE, type = 8))
}

matrix_rows_numeric <- function(x, rows) {
  rows <- as.integer(rows)
  value <- x[rows, , drop = FALSE]
  if (inherits(value, "float32")) value <- as.matrix(value)
  matrix(as.numeric(value), nrow = length(rows), byrow = FALSE)
}

exact_metric_distances <- function(x, query_row, candidate_rows, metric) {
  candidate_rows <- as.integer(candidate_rows)
  if (!length(candidate_rows)) return(numeric())
  query <- matrix_rows_numeric(x, query_row)[1L, ]
  candidates <- matrix_rows_numeric(x, candidate_rows)
  if (identical(metric, "euclidean")) {
    return(sqrt(rowSums((candidates - rep(query, each = nrow(candidates)))^2)))
  }
  if (identical(metric, "cosine")) {
    qnorm <- sqrt(sum(query^2))
    cnorm <- sqrt(rowSums(candidates^2))
    denom <- qnorm * cnorm
    similarity <- rowSums(candidates * rep(query, each = nrow(candidates))) / denom
    similarity[!is.finite(similarity)] <- 0
    return(1 - similarity)
  }
  if (identical(metric, "correlation")) {
    query <- query - mean(query)
    candidates <- candidates - rowMeans(candidates)
    qnorm <- sqrt(sum(query^2))
    cnorm <- sqrt(rowSums(candidates^2))
    denom <- qnorm * cnorm
    similarity <- rowSums(candidates * rep(query, each = nrow(candidates))) / denom
    similarity[!is.finite(similarity)] <- 0
    return(1 - similarity)
  }
  stop("Unsupported recall-audit metric: ", metric, call. = FALSE)
}

tie_aware_query_recall <- function(actual_indices, reference_indices,
                                   reference_distances, data, query_rows,
                                   metric, atol = 1e-5, rtol = 1e-4) {
  actual_indices <- as.matrix(actual_indices)
  reference_indices <- as.matrix(reference_indices)
  reference_distances <- as.matrix(reference_distances)
  n_query <- min(nrow(actual_indices), nrow(reference_indices),
                 nrow(reference_distances), length(query_rows))
  k <- min(ncol(actual_indices), ncol(reference_indices),
           ncol(reference_distances))
  identifier <- tie_aware <- rep(NA_real_, n_query)
  substitution <- logical(n_query)
  boundary_credit <- integer(n_query)

  for (i in seq_len(n_query)) {
    ref_ids <- as.integer(reference_indices[i, seq_len(k)])
    ref_dist <- as.numeric(reference_distances[i, seq_len(k)])
    got_ids <- unique(as.integer(actual_indices[i, seq_len(k)]))
    ref_ok <- is.finite(ref_ids) & is.finite(ref_dist)
    got_ids <- got_ids[is.finite(got_ids)]
    if (!any(ref_ok)) next
    ref_ids <- ref_ids[ref_ok]
    ref_dist <- ref_dist[ref_ok]
    denominator <- length(ref_ids)
    identifier[[i]] <- sum(got_ids %in% ref_ids) / denominator
    boundary <- max(ref_dist)
    tolerance <- atol + rtol * abs(boundary)
    strict_ids <- unique(ref_ids[ref_dist < boundary - tolerance])
    boundary_slots <- denominator - length(strict_ids)
    strict_credit <- sum(strict_ids %in% got_ids)
    possible_boundary <- setdiff(got_ids, strict_ids)
    known_boundary <- unique(ref_ids[abs(ref_dist - boundary) <= tolerance])
    accepted <- possible_boundary[possible_boundary %in% known_boundary]
    unknown <- setdiff(possible_boundary, known_boundary)
    if (length(unknown)) {
      exact_distance <- exact_metric_distances(
        data, query_rows[[i]], unknown, metric
      )
      accepted <- unique(c(
        accepted,
        unknown[abs(exact_distance - boundary) <= tolerance]
      ))
    }
    boundary_credit[[i]] <- min(boundary_slots, length(accepted))
    tie_aware[[i]] <- (strict_credit + boundary_credit[[i]]) / denominator
    substitution[[i]] <- tie_aware[[i]] > identifier[[i]] +
      sqrt(.Machine$double.eps)
  }
  list(
    identifier = identifier,
    tie_aware = tie_aware,
    boundary_substitution = substitution,
    boundary_credit = boundary_credit
  )
}

recall_inference_summary <- function(actual_indices, reference_indices,
                                     reference_distances, data, query_rows,
                                     metric, bootstrap_seed,
                                     confidence = 0.95,
                                     bootstrap_resamples = 1000L,
                                     atol = 1e-5, rtol = 1e-4) {
  query <- tie_aware_query_recall(
    actual_indices, reference_indices, reference_distances, data, query_rows,
    metric, atol = atol, rtol = rtol
  )
  finite_identifier <- query$identifier[is.finite(query$identifier)]
  finite_tie <- query$tie_aware[is.finite(query$tie_aware)]
  list(
    identifier_mean = if (length(finite_identifier)) mean(finite_identifier) else NA_real_,
    tie_aware_mean = if (length(finite_tie)) mean(finite_tie) else NA_real_,
    identifier_lcb = query_bootstrap_lcb(
      finite_identifier, confidence, bootstrap_resamples, bootstrap_seed
    ),
    tie_aware_lcb = query_bootstrap_lcb(
      finite_tie, confidence, bootstrap_resamples, bootstrap_seed + 1L
    ),
    tie_substitution_query_fraction = if (length(query$boundary_substitution)) {
      mean(query$boundary_substitution)
    } else NA_real_,
    mean_boundary_credit = if (length(query$boundary_credit)) {
      mean(query$boundary_credit)
    } else NA_real_,
    n_independent_queries = length(finite_tie),
    confidence = confidence,
    bootstrap_resamples = as.integer(bootstrap_resamples),
    query = query
  )
}
