#ifndef FAISSR_NORMALIZE_HPP
#define FAISSR_NORMALIZE_HPP

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <stdexcept>
#include <vector>

namespace faissr {

// Scale before centering or squaring; cast to float only after normalization.
template <typename Read>
bool normalized_row(const int p, const bool center, Read read,
                    std::vector<double>& row) {
  row.assign(p, 0.0);
  double scale = 0.0;
  bool constant = true;
  const double first = read(0);
  for (int c = 0; c < p; ++c) {
    const double value = read(c);
    if (!std::isfinite(value)) {
      throw std::invalid_argument("metric normalization requires finite values");
    }
    scale = std::max(scale, std::abs(value));
    constant = constant && value == first;
  }
  if (scale == 0.0 || (center && constant)) return false;

  double mean = 0.0;
  for (int c = 0; c < p; ++c) {
    row[c] = read(c) / scale;
    if (center) mean += row[c];
  }
  if (center) mean /= static_cast<double>(p);
  double norm2 = 0.0;
  for (int c = 0; c < p; ++c) {
    row[c] -= mean;
    norm2 += row[c] * row[c];
  }
  const double norm = std::sqrt(norm2);
  if (norm == 0.0) {
    std::fill(row.begin(), row.end(), 0.0);
    return false;
  }
  for (double& value : row) value /= norm;
  return true;
}

template <typename Read>
std::vector<char> normalized_float_matrix(
    const int n, const int p, const bool center, const bool column_major,
    Read read, std::vector<float>& output) {
  output.resize(static_cast<std::size_t>(n) * p);
  std::vector<char> zero(n);
  std::vector<double> row;
  for (int r = 0; r < n; ++r) {
    zero[r] = !normalized_row(p, center, [&](int c) { return read(r, c); }, row);
    for (int c = 0; c < p; ++c) {
      const std::size_t offset = column_major ?
        static_cast<std::size_t>(c) * n + r : static_cast<std::size_t>(r) * p + c;
      output[offset] = static_cast<float>(row[c]);
    }
  }
  return zero;
}

}  // namespace faissr

#endif
