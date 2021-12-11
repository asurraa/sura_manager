import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sura_manager/src/imanager.dart';

import 'future_manager_builder.dart';
import 'type.dart';

///This class is inspired from SWR in React
///[FutureManager] is a wrap around [Future] and [ChangeNotifier]
///
///[FutureManager] use [FutureManagerBuilder] instead of FutureBuilder to handle data
///
///[FutureManager] provide a method [asyncOperation] to handle or call async function
class FutureManager<T> extends IManager<T> {
  ///A future function that return the type of T
  final FutureFunction<T>? futureFunction;

  /// A function that call after [asyncOperation] is success and you want to manipulate data before
  /// adding it to manager
  final SuccessCallBack<T>? onSuccess;

  /// A function that call after everything is done
  final VoidCallback? onDone;

  /// A function that call after there is an error in our [asyncOperation]
  final ErrorCallBack? onError;

  /// if [reloading] is true, every time there's a new data, FutureManager will reset it's state to loading
  /// default value is [false]
  final bool reloading;

  ///Create a FutureManager instance, You can define a [futureFunction] here then [asyncOperation] will be call immediately
  FutureManager({
    this.futureFunction,
    this.reloading = true,
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

  ///
  T? _data;
  dynamic _error;
  ManagerViewState _viewState = ManagerViewState.loading;
  ValueNotifier<ManagerProcessState> _processingState =
      ValueNotifier(ManagerProcessState.idle);

  ManagerViewState get viewState => _viewState;
  ValueNotifier<ManagerProcessState> get processingState => _processingState;
  T? get data => _data;
  dynamic get error => _error;

  ///
  bool get isRefreshing => _data != null || _error != null;
  bool get hasData => _data != null;
  bool get hasError => _error != null;
  bool _disposed = false;

  @override
  Widget when({
    required Widget Function(T) ready,
    Widget? loading,
    Widget Function(dynamic)? error,
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
  Future<T?> Function({
    bool? reloading,
    SuccessCallBack<T>? onSuccess,
    VoidCallback? onDone,
    ErrorCallBack? onError,
    bool? throwError,
  }) refresh = ({reloading, onSuccess, onDone, onError, throwError}) async {
    print("refresh is depend on asyncOperation,"
        " You need to call asyncOperation once before you can call refresh");
    return null;
  };

  @override
  Future<T?> asyncOperation(
    FutureFunction<T> futureFunction, {
    bool? reloading,
    SuccessCallBack<T>? onSuccess,
    VoidCallback? onDone,
    ErrorCallBack? onError,
    bool throwError = false,
  }) async {
    refresh = ({reloading, onSuccess, onDone, onError, throwError}) async {
      bool shouldReload = reloading ?? this.reloading;
      SuccessCallBack<T>? successCallBack = onSuccess ?? this.onSuccess;
      ErrorCallBack? errorCallBack = onError ?? this.onError;
      VoidCallback? onOperationDone = onDone ?? this.onDone;
      bool? shouldThrowError = throwError ?? false;
      //
      bool triggerError = true;
      if (isRefreshing) {
        triggerError = shouldReload;
      }
      try {
        this.resetData(updateViewState: shouldReload);
        future = futureFunction.call();
        T result = await future!;
        if (successCallBack != null) {
          result = await successCallBack.call(result);
        }
        this.updateData(result);
        return result;
      } catch (exception) {
        ///Only update viewState if [triggerError] is true
        this.addError(exception, updateViewState: triggerError);
        errorCallBack?.call(exception);
        if (shouldThrowError) {
          throw exception;
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
    );
  }

  void _updateManagerViewState(ManagerViewState state) {
    if (_disposed) return;
    this._viewState = state;
    notifyListeners();
  }

  void _updateManagerProcessState(ManagerProcessState state) {
    if (_disposed) return;

    ///notify the ValueNotifier because it doesn't update if data is the same
    if (this._processingState.value == state) {
      this._processingState.notifyListeners();
    }
    this._processingState.value = state;
  }

  ///Similar to [updateData] but provide current [data] in Manager as a param
  ///Even this function is mark as async, this function shouldn't be use as async
  ///If you want to update data with async, use [asyncOperation] instead
  void modifyData(FutureOr<T> Function(T?) onChange) async {
    T? data = await onChange(_data);
    updateData(data);
  }

  ///Update current data in our Manager
  ///Ignore if data is null
  ///Use [resetData] instead if you want to reset to [loading] state
  @override
  void updateData(T? data) {
    if (data != null) {
      _data = data;
      _error = null;
      _updateManagerProcessState(ManagerProcessState.ready);
      _updateManagerViewState(ManagerViewState.ready);
    }
  }

  ///Reset all [data] and [error] to [loading] state
  @override
  void resetData({bool updateViewState = true}) {
    if (updateViewState) {
      this._error = null;
      this._data = null;
      _updateManagerViewState(ManagerViewState.loading);
    } else {
      notifyListeners();
    }
    _updateManagerProcessState(ManagerProcessState.processing);
  }

  ///Add [error] our current manager, reset current [data] to null
  @override
  void addError(dynamic error, {bool updateViewState = true}) {
    this._error = error;
    if (updateViewState) {
      this._data = null;
      _updateManagerViewState(ManagerViewState.error);
    } else {
      notifyListeners();
    }
    _updateManagerProcessState(ManagerProcessState.error);
  }

  @override
  void dispose() {
    _data = null;
    _error = null;
    _processingState.dispose();
    _disposed = true;
    super.dispose();
  }
}
