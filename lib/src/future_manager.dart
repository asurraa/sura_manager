import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:sura_manager/src/imanager.dart';

import 'future_manager_builder.dart';
import 'manager_cache.dart';
import 'type.dart';

///[FutureManager] is a wrap around [Future] and [ChangeNotifier]
///
///[FutureManager] use [FutureManagerBuilder] instead of FutureBuilder to handle data
///
///[FutureManager] provide a method [asyncOperation] to handle or call async function
class FutureManager<T extends Object> extends IManager<T> {
  ///A future function that return the type of T
  final FutureFunction<T>? futureFunction;

  ///A function that call after [asyncOperation] is success and you want to manipulate data before
  ///adding it to manager
  final SuccessCallBack<T>? onSuccess;

  ///A function that call after everything is done
  final VoidCallback? onDone;

  /// A function that call after there is an error in our [asyncOperation]
  final ErrorCallBack? onError;

  /// if [reloading] is true, every time there's a new data, FutureManager will reset it's state to loading
  /// default value is [false]
  final bool reloading;

  ///An option to cache Manager's data
  ///This is not a storage cache or memory cache.
  ///Data is cache within lifetime of FutureManager only
  final ManagerCacheOption cacheOption;

  ///Create a FutureManager instance, You can define a [futureFunction] here then [asyncOperation] will be call immediately
  FutureManager({
    this.futureFunction,
    this.reloading = true,
    this.cacheOption = const ManagerCacheOption.non(),
    this.onSuccess,
    this.onDone,
    this.onError,
  }) {
    if (futureFunction != null) {
      asyncOperation(
        futureFunction!,
        reloading: reloading,
        onSuccess: onSuccess,
        onDone: onDone,
        onError: onError,
      );
    }
  }

  ///The Future that this class is doing in [asyncOperation]
  ///Sometime you want to use [FutureManager] class with FutureBuilder, so you can use this field
  Future<T>? future;

  ///View state of Manager that control which Widget to build in FutureManagerBuilder
  ManagerViewState get viewState => _viewState;
  ManagerViewState _viewState = ManagerViewState.loading;

  ///Processing state of Manager. Usually useful for any lister
  ValueNotifier<ManagerProcessState> get processingState => _processingState;
  final ValueNotifier<ManagerProcessState> _processingState =
      ValueNotifier(ManagerProcessState.idle);

  ///Manager's data
  T? get data => _data;
  T? _data;

  ///Manager's error
  FutureManagerError? get error => _error;
  FutureManagerError? _error;

  //A field for checking state of Manager
  bool get isRefreshing =>
      hasDataOrError &&
      _processingState.value == ManagerProcessState.processing;
  bool get hasDataOrError => (hasData || hasError);
  bool get hasData => _data != null;
  bool get hasError => _error != null;
  bool _disposed = false;

  //Cache option
  int? _lastCacheDuration;

  @override
  Widget when({
    required Widget Function(T) ready,
    Widget? loading,
    Widget Function(FutureManagerError)? error,
  }) {
    return FutureManagerBuilder<T>(
      futureManager: this,
      ready: (context, data) => ready(data),
      loading: loading,
      error: error,
    );
  }

  ///Similar to [when] but Only listen and display [data]. Default to Display blank when there is [loading] and [error] But can still customize
  Widget listen({
    required Widget Function(T) ready,
    Widget loading = const SizedBox(),
    Widget Function(FutureManagerError) error = EmptyErrorFunction,
  }) {
    return FutureManagerBuilder<T>(
      futureManager: this,
      ready: (context, data) => ready(data),
      loading: loading,
      error: error,
    );
  }

  ///refresh is a function that call [asyncOperation] again,
  ///but doesn't reserve configuration
  ///return null if [futureFunction] hasn't been initialize
  late Future<T?> Function({
    bool? reloading,
    SuccessCallBack<T>? onSuccess,
    VoidCallback? onDone,
    ErrorCallBack? onError,
    bool throwError,
    bool useCache,
  }) refresh = _emptyRefreshFunction;

  Future<T?> _emptyRefreshFunction(
      {reloading, onSuccess, onDone, onError, throwError, useCache}) async {
    log("refresh() is depend on asyncOperation(),"
        " You need to call asyncOperation() once before you can call refresh()");
    return null;
  }

  @override
  Future<T?> asyncOperation(
    FutureFunction<T> futureFunction, {
    bool? reloading,
    SuccessCallBack<T>? onSuccess,
    VoidCallback? onDone,
    ErrorCallBack? onError,
    bool throwError = false,
    bool useCache = true,
  }) async {
    refresh = (
        {reloading,
        onSuccess,
        onDone,
        onError,
        throwError = false,
        useCache = false}) async {
      bool shouldReload = reloading ?? this.reloading;
      SuccessCallBack<T>? successCallBack = onSuccess ?? this.onSuccess;
      ErrorCallBack? errorCallBack = onError ?? this.onError;
      VoidCallback? onOperationDone = onDone ?? this.onDone;
      bool shouldThrowError = throwError;
      //useCache is always default to `false` if we call refresh directly
      if (_enableCache && useCache) {
        return data!;
      }
      //
      bool triggerError = true;
      if (hasDataOrError) {
        triggerError = shouldReload;
      }
      try {
        await resetData(updateViewState: shouldReload);
        future = futureFunction.call();
        T result = await future!;
        if (successCallBack != null) {
          result = await successCallBack.call(result);
        }
        updateData(result);
        return result;
      } catch (exception, stackTrace) {
        FutureManagerError error = FutureManagerError(
          exception: exception,
          stackTrace: stackTrace,
        );

        ///Only update viewState if [triggerError] is true
        addError(error, updateViewState: triggerError);
        errorCallBack?.call(error);
        if (shouldThrowError) {
          rethrow;
        }
        return null;
      } finally {
        onOperationDone?.call();
      }
    };
    return refresh(
      reloading: reloading,
      onSuccess: onSuccess,
      onDone: onDone,
      onError: onError,
      throwError: throwError,
      useCache: useCache,
    );
  }

  bool get _enableCache {
    if (_lastCacheDuration == null) return false;

    bool lastCacheIsExpired() {
      int now = DateTime.now().millisecondsSinceEpoch;
      int expiredTime =
          _lastCacheDuration! + cacheOption.cacheTime.inMilliseconds;
      return now > expiredTime;
    }

    return cacheOption.useCache && hasData && !lastCacheIsExpired();
  }

  ///Custom [notifyListeners] to support Future that can be useful in some case
  void _notifyListeners({required bool useMicrotask}) {
    if (useMicrotask) {
      Future.microtask(() => notifyListeners());
    } else {
      notifyListeners();
    }
  }

  ///[useMicrotask] param can be use to prevent schedule rebuilt while navigating or rebuilt
  void _updateManagerViewState(ManagerViewState state,
      {bool useMicrotask = false}) {
    if (_disposed) return;
    _viewState = state;
    _notifyListeners(useMicrotask: useMicrotask);
  }

  ///Wrap with [microtask] to prevent schedule rebuilt while navigating or rebuilt
  void _updateManagerProcessState(ManagerProcessState state,
      {bool useMicrotask = false}) {
    if (_disposed) return;

    void update() {
      if (_processingState.value == state) {
        _processingState.notifyListeners();
      }
      _processingState.value = state;
    }

    ///notify the ValueNotifier because it doesn't update if data is the same
    if (useMicrotask) {
      Future.microtask(update);
    } else {
      update();
    }
  }

  ///Similar to [updateData] but provide current current [data] in Manager as param.
  ///return updated [data] result once completed.
  Future<T?> modifyData(FutureOr<T> Function(T?) onChange) async {
    T? data = await onChange(_data);
    updateData(data);
    return data;
  }

  ///Update current data in our Manager.
  ///Ignore if data is null.
  ///Use [resetData] instead if you want to reset to [loading] state
  @override
  T? updateData(T? data, {bool useMicrotask = false}) {
    if (data != null) {
      _data = data;
      _error = null;
      _updateManagerProcessState(ManagerProcessState.ready,
          useMicrotask: useMicrotask);
      _updateManagerViewState(ManagerViewState.ready,
          useMicrotask: useMicrotask);
      _updateLastCacheDuration();
      return data;
    }
    return null;
  }

  void _updateLastCacheDuration() {
    if (cacheOption.useCache) {
      _lastCacheDuration = DateTime.now().millisecondsSinceEpoch;
    }
  }

  ///Clear the error on this manager
  ///Only work when ViewState isn't error
  ///Best use case with Pagination when there is an error and you want to clear the error to show loading again
  void clearError() {
    if (viewState != ManagerViewState.error) {
      _error = null;
      _notifyListeners(useMicrotask: false);
    }
  }

  ///Add [error] our current manager, reset current [data] if [updateViewState] to null
  ///
  @override
  void addError(
    Object error, {
    bool updateViewState = true,
    bool useMicrotask = false,
  }) {
    FutureManagerError err = error is! FutureManagerError
        ? FutureManagerError(exception: error)
        : error;
    _error = err;
    if (updateViewState) {
      _data = null;
      _updateManagerViewState(
        ManagerViewState.error,
        useMicrotask: useMicrotask,
      );
    } else {
      _notifyListeners(useMicrotask: useMicrotask);
    }
    _updateManagerProcessState(
      ManagerProcessState.error,
      useMicrotask: useMicrotask,
    );
  }

  ///Reset all [data] and [error] to [loading] state if [updateViewState] is true only.
  ///if [updateViewState] is false, only notifyListener and update ManagerProcessState.
  @override
  Future<void> resetData({bool updateViewState = true}) async {
    const bool useMicroTask = true;
    if (updateViewState) {
      _error = null;
      _data = null;
      _updateManagerViewState(
        ManagerViewState.loading,
        useMicrotask: useMicroTask,
      );
    } else {
      _notifyListeners(useMicrotask: useMicroTask);
    }
    _updateManagerProcessState(
      ManagerProcessState.processing,
      useMicrotask: useMicroTask,
    );
  }

  @override
  String toString() {
    String logContent =
        "Data: $_data, Error: $_error, ViewState: $viewState, ProcessState: $processingState";
    if (_lastCacheDuration != null) {
      logContent +=
          ", cacheDuration: ${DateTime.fromMillisecondsSinceEpoch(_lastCacheDuration!)}";
    }
    return logContent;
  }

  @override
  void dispose() {
    _data = null;
    _error = null;
    _lastCacheDuration = null;
    _processingState.dispose();
    _disposed = true;
    super.dispose();
  }
}
