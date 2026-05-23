-dontwarn com.google.android.libraries.places.api.Places
-dontwarn com.google.android.libraries.places.api.model.AddressComponent
-dontwarn com.google.android.libraries.places.api.model.AddressComponents
-dontwarn com.google.android.libraries.places.api.model.AutocompletePrediction
-dontwarn com.google.android.libraries.places.api.model.AutocompleteSessionToken
-dontwarn com.google.android.libraries.places.api.model.Place$Field
-dontwarn com.google.android.libraries.places.api.model.Place
-dontwarn com.google.android.libraries.places.api.model.TypeFilter
-dontwarn com.google.android.libraries.places.api.net.FetchPlaceRequest
-dontwarn com.google.android.libraries.places.api.net.FetchPlaceResponse
-dontwarn com.google.android.libraries.places.api.net.FindAutocompletePredictionsRequest$Builder
-dontwarn com.google.android.libraries.places.api.net.FindAutocompletePredictionsRequest
-dontwarn com.google.android.libraries.places.api.net.FindAutocompletePredictionsResponse
-dontwarn com.google.android.libraries.places.api.net.PlacesClient
-dontwarn com.stripe.android.stripecardscan.cardscan.CardScanSheet$CardScanResultCallback
-dontwarn com.stripe.android.stripecardscan.cardscan.CardScanSheet$Companion
-dontwarn com.stripe.android.stripecardscan.cardscan.CardScanSheet
-dontwarn com.stripe.android.stripecardscan.cardscan.CardScanSheetResult$Completed
-dontwarn com.stripe.android.stripecardscan.cardscan.CardScanSheetResult$Failed
-dontwarn com.stripe.android.stripecardscan.cardscan.CardScanSheetResult
-dontwarn com.stripe.android.stripecardscan.cardscan.exception.UnknownScanException
-dontwarn com.stripe.android.stripecardscan.payment.card.ScannedCard

# flutter_local_notifications
-keep class com.dexterous.** { *; }
-keep class androidx.core.app.** { *; }

# Firebase plugins (Pigeon-based channels)
-keep class dev.flutter.pigeon.** { *; }
-keep class io.flutter.plugins.firebase.** { *; }
-keep class com.google.firebase.** { *; }

# Flutter plugin registrant
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keep class io.flutter.plugin.common.** { *; }
