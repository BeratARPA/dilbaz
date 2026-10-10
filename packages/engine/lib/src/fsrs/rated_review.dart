import 'package:dilbaz_engine/src/fsrs/review_rating.dart';

/// One rated review of a card, as logged in `attempts` (`rating` and the
/// attempt time, UTC). Replaying these rebuilds the card (I-03).
typedef RatedReview = ({ReviewRating rating, DateTime at});
