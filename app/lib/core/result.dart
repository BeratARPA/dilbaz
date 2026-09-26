/// Outcome of an operation whose failures are expected; expected failures
/// are values, not exceptions.
sealed class Result<T, E> {
  const new();
}

final class Ok<T, E> extends Result<T, E> {
  const new(this.value);

  final T value;
}

final class Err<T, E> extends Result<T, E> {
  const new(this.error);

  final E error;
}
