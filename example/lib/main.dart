import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:sura_flutter/sura_flutter.dart';
import 'package:sura_manager/sura_manager.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SuraProvider(
      errorWidget: (error, onRefresh) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(error.toString()),
              TextButton(
                  onPressed: onRefresh, child: const Icon(Icons.refresh)),
            ],
          ),
        );
      },
      child: MaterialApp(
        title: 'Sura Manager Example',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: const MyHomePage(),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

late FutureManager<int> dataManager = FutureManager(
  reloading: true,
  onError: (err) {},
);

class _MyHomePageState extends State<MyHomePage> {
  @override
  void initState() {
    dataManager.asyncOperation(() async {
      await Future.delayed(const Duration(milliseconds: 1500));
      //bool error = false;
      //Random().nextBool();
      //if (error) throw "Error while getting data";
      //debugPrint("Get data done");
      return Random().nextInt(20);
    });

    dataManager.addListener(() {
      debugPrint(dataManager.toString());
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    //Use with FutureManagerBuilder
    return Scaffold(
      appBar: AppBar(
        title: const Text("FutureManager example"),
      ),
      body: FutureManagerBuilder<int>(
        futureManager: dataManager,
        onRefreshing: () => const RefreshProgressIndicator(),
        loading: const Center(child: CircularProgressIndicator()),
        onError: (err) {
          //debugdebugPrint("We got an error: $err");
        },
        onData: (data) {
          debugPrint("We got a data: $data");
        },
        ready: (context, data) {
          debugPrint("Rebuild");
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("My data: $data"),
                const SpaceY(24),
                ElevatedButton(
                  onPressed: () async {
                    await dataManager.modifyData((data) {
                      return data! + 10;
                    });
                  },
                  child: const Text("Add 10"),
                ),
                const SpaceY(24),
                ElevatedButton(
                  onPressed: dataManager.refresh,
                  child: const Text("Refresh"),
                ),
                const SpaceY(24),
                ElevatedButton(
                  onPressed: () => dataManager.refresh(reloading: false),
                  child: const Text("Refresh without reload"),
                ),
                const SpaceY(24),
                ElevatedButton(
                  onPressed: () async {
                    dataManager.addError(
                        const FutureManagerError(exception: "exception"));
                    print(dataManager.error.runtimeType.toString());
                  },
                  child: const Text("Add error"),
                ),
                const SpaceY(24),
                ElevatedButton(
                  onPressed: dataManager.resetData,
                  child: const Text("Reset"),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          SuraPageNavigator.push(context, const SuraManagerWithPagination());
        },
        child: const Icon(Icons.assessment),
      ),
    );
  }
}

class SuraManagerWithPagination extends StatefulWidget {
  const SuraManagerWithPagination({Key? key}) : super(key: key);

  @override
  _SuraManagerWithPaginationState createState() =>
      _SuraManagerWithPaginationState();
}

class _SuraManagerWithPaginationState extends State<SuraManagerWithPagination> {
  FutureManager<UserResponse> userController = FutureManager();
  int currentPage = 1;
  int maxTimeToShowError = 0;

  Future fetchData([bool reload = false]) async {
    await Future.delayed(const Duration(seconds: 1));
    if (reload) {
      currentPage = 1;
    }
    userController.asyncOperation(
      () async {
        if (currentPage > 1 && maxTimeToShowError < 2) {
          maxTimeToShowError++;
          throw "Expected error thrown from asyncOperation";
        }

        final response = await Dio().get(
          "https://express-boilerplate-dev.lynical.com/api/user/all",
          queryParameters: {
            "page": currentPage,
            "count": 10,
          },
        );
        return UserResponse.fromJson(response.data);
      },
      onSuccess: (response) {
        if (userController.hasData) {
          response.users = [...userController.data!.users, ...response.users];
        }
        currentPage += 1;
        return response;
      },
      reloading: reload,
    );
  }

  @override
  void initState() {
    ///Test microtask set to true
    dataManager.addError(const FutureManagerError(exception: "100"),
        useMicrotask: true);
    fetchData();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Fetch all users with pagination")),
      body: FutureManagerBuilder<UserResponse>(
        futureManager: userController,
        ready: (context, UserResponse response) {
          return SuraPaginatedList(
            itemCount: response.users.length,
            hasMoreData: response.hasMoreData,
            padding: EdgeInsets.zero,
            hasError: userController.hasError,
            itemBuilder: (context, index) {
              final user = response.users[index];
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person),
                ),
                onTap: () {},
                title: Text("${index + 1}: ${user.firstName} ${user.lastName}"),
                subtitle: Text(user.email!),
              );
            },
            dataLoader: fetchData,
            errorWidget: Column(
              children: [
                Text(userController.error.toString()),
                IconButton(
                  onPressed: () {
                    userController.addError("null", updateViewState: false);
                    fetchData();
                  },
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class UserResponse {
  List<UserModel> users;
  final Pagination? pagination;

  UserResponse({this.pagination, required this.users});

  bool get hasMoreData =>
      pagination != null ? users.length < pagination!.totalItems : false;

  factory UserResponse.fromJson(Map<String, dynamic> json) => UserResponse(
        users: json["data"] == null
            ? []
            : List<UserModel>.from(
                json["data"].map((x) => UserModel.fromJson(x))),
        pagination: json["pagination"] == null
            ? null
            : Pagination.fromJson(json["pagination"]),
      );
}

class UserModel {
  UserModel({
    this.id,
    this.email,
    this.firstName,
    this.lastName,
    this.avatar,
  });

  String? id;
  String? email;
  String? firstName;
  String? lastName;
  String? avatar;

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json["_id"],
        email: json["email"],
        firstName: json["first_name"],
        lastName: json["last_name"],
        avatar: json["profile_img"],
      );
}

class Pagination {
  Pagination({
    required this.page,
    required this.totalItems,
    required this.totalPage,
  });

  num page;
  num totalItems;
  num totalPage;

  factory Pagination.fromJson(Map<String, dynamic> json) => Pagination(
        page: json["page"] ?? 0,
        totalItems: json["total_items"] ?? 0,
        totalPage: json["total_page"] ?? 0,
      );
}
