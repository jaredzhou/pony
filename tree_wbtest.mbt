///|
test "tree" {
  let r = Router::Router()
  let h = Handler(ctx => println(ctx))
  let h2 = Handler(ctx => println(ctx))
  r.add(Get, "/", h, name="h")
  r.add(Get, "/favicon.ico", h, name="h")
  r.add(Get, "/pages/*", h, name="h")
  r.add(Get, "/article", h, name="h")
  r.add(Get, "/article/", h, name="h")
  r.add(Get, "/article/near", h, name="h")
  r.add(Get, "/article/{id}", h, name="h")
  r.add(Get, "/article/{id}", h2, name="h2")
  r.add(Get, "/article/{id}", h2, name="h2") //duplicate will have no effect
  r.add(Get, "/article/@{user}", h, name="h")
  r.add(Get, "/article/{sup}/{opts}", h, name="h")
  r.add(Get, "/article/{id}/{opts}", h, name="h") //overwrite above route, latest wins
  r.add(Get, "/article/{iffd}/edit", h, name="h")
  r.add(Get, "/article/{id}//related", h, name="h")
  r.add(Get, "/article/slug/{month}/-/{day}/{year}", h, name="h")
  r.add(Get, "/admin/user", h, name="h")
  r.add(Get, "/admin/user/", h, name="h")
  r.add(Get, "/admin/user/", h2, name="h2") // overwrite above route, latest wins
  r.add(Get, "/admin/user//{id}", h, name="h")
  r.add(Get, "/admin/user/{id}", h, name="h")
  r.add(Get, "/admin/apps/{id}", h, name="h")
  r.add(Get, "/admin/apps/{id}/*", h, name="h")
  r.add(Get, "/admin/*", h, name="h")
  r.add(Get, "/admin/*", h2, name="h2") // overwrite above route, latest wins
  r.add(Get, "/users/{userID}/profile", h, name="h")
  r.add(Get, "/users/super/*", h, name="h")
  r.add(Get, "/users/*", h, name="h")
  r.add(Get, "/hubs/{hubID}/view", h, name="h")
  r.add(Get, "/hubs/{hubID}/view/*", h, name="h")
  r.add(Get, "/hubs/{hubID}/*", h, name="h")
  r.add(Get, "/hubs/{hubID}/users", h, name="h")
  inspect(
    r,
    content=(
      #|Static()
      #|    └── Static(/) Get(/)
      #|        ├── Static(favicon.ico) Get(/favicon.ico)
      #|        ├── Static(pages/)
      #|        │   w── * Get(/pages/*)
      #|        ├── Static(a)
      #|        │   ├── Static(rticle) Get(/article)
      #|        │   │   └── Static(/) Get(/article/)
      #|        │   │       ├── Static(near) Get(/article/near)
      #|        │   │       ├── Static(@)
      #|        │   │       │   p── Param(user,/) Get(/article/@{user})
      #|        │   │       ├── Static(slug/)
      #|        │   │       │   p── Param(month,/)
      #|        │   │       │       └── Static(/-/)
      #|        │   │       │           p── Param(day,/)
      #|        │   │       │               └── Static(/)
      #|        │   │       │                   p── Param(year,/) Get(/article/slug/{month}/-/{day}/{year})
      #|        │   │       p── Param(id,/) Get(/article/{id})
      #|        │   │           └── Static(/)
      #|        │   │               ├── Static(edit) Get(/article/{iffd}/edit)
      #|        │   │               ├── Static(/related) Get(/article/{id}//related)
      #|        │   │               p── Param(opts,/) Get(/article/{id}/{opts})
      #|        │   └── Static(dmin/)
      #|        │       ├── Static(user) Get(/admin/user)
      #|        │       │   └── Static(/) Get(/admin/user/)
      #|        │       │       ├── Static(/)
      #|        │       │       │   p── Param(id,/) Get(/admin/user//{id})
      #|        │       │       p── Param(id,/) Get(/admin/user/{id})
      #|        │       ├── Static(apps/)
      #|        │       │   p── Param(id,/) Get(/admin/apps/{id})
      #|        │       │       └── Static(/)
      #|        │       │           w── * Get(/admin/apps/{id}/*)
      #|        │       w── * Get(/admin/*)
      #|        ├── Static(users/)
      #|        │   ├── Static(super/)
      #|        │   │   w── * Get(/users/super/*)
      #|        │   p── Param(userID,/)
      #|        │   │   └── Static(/profile) Get(/users/{userID}/profile)
      #|        │   w── * Get(/users/*)
      #|        └── Static(hubs/)
      #|            p── Param(hubID,/)
      #|                └── Static(/)
      #|                    ├── Static(view) Get(/hubs/{hubID}/view)
      #|                    │   └── Static(/)
      #|                    │       w── * Get(/hubs/{hubID}/view/*)
      #|                    ├── Static(users) Get(/hubs/{hubID}/users)
      #|                    w── * Get(/hubs/{hubID}/*)
      #|
    ),
  )
  let result = r.route(Get, "/")
  assert_true(
    result is RouteResult::Found(ep, _) && ep.pattern == "/" && ep.name == "h",
  )
  let result = r.route(Get, "/favicon.ico")
  assert_true(
    result is RouteResult::Found(ep, _) && ep.pattern == "/favicon.ico",
  )
  let result = r.route(Get, "/pages")
  assert_true(result is RouteResult::NotFound)
  let result = r.route(Get, "/pages/")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/pages/*" &&
    ep.to_paramKV_array(param_values) is [ParamKV("*", "")],
  )
  let result = r.route(Get, "/pages/anything/here")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/pages/*" &&
    ep.to_paramKV_array(param_values) is [ParamKV("*", "anything/here")],
  )
  let result = r.route(Get, "/article/123")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/article/{id}" &&
    ep.to_paramKV_array(param_values) is [ParamKV("id", "123")],
  )
  let result = r.route(Get, "/article")
  assert_true(
    result is RouteResult::Found(ep, _) &&
    ep.pattern == "/article" &&
    ep.name == "h",
  )
  let result = r.route(Get, "/article/")
  assert_true(
    result is RouteResult::Found(ep, _) &&
    ep.pattern == "/article/" &&
    ep.name == "h",
  )
  let result = r.route(Get, "/article/near")
  assert_true(
    result is RouteResult::Found(ep, _) &&
    ep.pattern == "/article/near" &&
    ep.name == "h",
  )
  let result = r.route(Get, "/article/neard")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/article/{id}" &&
    ep.to_paramKV_array(param_values) is [ParamKV("id", "neard")] &&
    ep.name == "h2",
  )
  let result = r.route(Get, "/article/123/456")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/article/{id}/{opts}" &&
    ep.to_paramKV_array(param_values)
    is [ParamKV("id", "123"), ParamKV("opts", "456")] &&
    ep.name == "h",
  )
  let result = r.route(Get, "/article/@peter")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/article/@{user}" &&
    ep.to_paramKV_array(param_values) is [ParamKV("user", "peter")] &&
    ep.name == "h",
  )
  let result = r.route(Get, "/article/22//related")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/article/{id}//related" &&
    ep.to_paramKV_array(param_values) is [ParamKV("id", "22")] &&
    ep.name == "h",
  )
  let result = r.route(Get, "/article/111/edit")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/article/{iffd}/edit" &&
    ep.to_paramKV_array(param_values) is [ParamKV("iffd", "111")] &&
    ep.name == "h",
  )
  let result = r.route(Get, "/article/slug/sept/-/4/2015")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/article/slug/{month}/-/{day}/{year}" &&
    ep.to_paramKV_array(param_values)
    is [ParamKV("month", "sept"), ParamKV("day", "4"), ParamKV("year", "2015")] &&
    ep.name == "h",
  )
  let result = r.route(Get, "/article/:id")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/article/{id}" &&
    ep.to_paramKV_array(param_values) is [ParamKV("id", ":id")] &&
    ep.name == "h2",
  )
  let result = r.route(Get, "/admin/user")
  assert_true(
    result is RouteResult::Found(ep, _) &&
    ep.pattern == "/admin/user" &&
    ep.name == "h",
  )
  let result = r.route(Get, "/admin/user/")
  assert_true(
    result is RouteResult::Found(ep, _) &&
    ep.pattern == "/admin/user/" &&
    ep.name == "h2",
  )
  let result = r.route(Get, "/admin/user/1")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/admin/user/{id}" &&
    ep.to_paramKV_array(param_values) is [ParamKV("id", "1")] &&
    ep.name == "h",
  )
  let result = r.route(Get, "/admin/user//1")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/admin/user//{id}" &&
    ep.to_paramKV_array(param_values) is [ParamKV("id", "1")] &&
    ep.name == "h",
  )
  let result = r.route(Get, "/admin/hi")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/admin/*" &&
    ep.to_paramKV_array(param_values) is [ParamKV("*", "hi")] &&
    ep.name == "h2",
  )
  let result = r.route(Get, "/admin/lots/of/:fun")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/admin/*" &&
    ep.to_paramKV_array(param_values) is [ParamKV("*", "lots/of/:fun")] &&
    ep.name == "h2",
  )
  let result = r.route(Get, "/admin/apps/333")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/admin/apps/{id}" &&
    ep.to_paramKV_array(param_values) is [ParamKV("id", "333")] &&
    ep.name == "h",
  )
  let result = r.route(Get, "/admin/apps/333/woot")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/admin/apps/{id}/*" &&
    ep.to_paramKV_array(param_values)
    is [ParamKV("id", "333"), ParamKV("*", "woot")] &&
    ep.name == "h",
  )
  let result = r.route(Get, "/hubs/123/view")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/hubs/{hubID}/view" &&
    ep.to_paramKV_array(param_values) is [ParamKV("hubID", "123")] &&
    ep.name == "h",
  )
  let result = r.route(Get, "/hubs/123/view/index.html")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/hubs/{hubID}/view/*" &&
    ep.to_paramKV_array(param_values)
    is [ParamKV("hubID", "123"), ParamKV("*", "index.html")] &&
    ep.name == "h",
  )
  let result = r.route(Get, "/hubs/123/users")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/hubs/{hubID}/users" &&
    ep.to_paramKV_array(param_values) is [ParamKV("hubID", "123")] &&
    ep.name == "h",
  )
  let result = r.route(Get, "/users/123/profile")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/users/{userID}/profile" &&
    ep.to_paramKV_array(param_values) is [ParamKV("userID", "123")] &&
    ep.name == "h",
  )
  let result = r.route(Get, "/users/super/123/okay/yes")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/users/super/*" &&
    ep.to_paramKV_array(param_values) is [ParamKV("*", "123/okay/yes")] &&
    ep.name == "h",
  )
  let result = r.route(Get, "/users/123/okay/yes")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/users/*" &&
    ep.to_paramKV_array(param_values) is [ParamKV("*", "123/okay/yes")] &&
    ep.name == "h",
  )
}

///|
async test "tree more" {
  let r = Router::Router()
  let hStub = Handler(ctx => println(ctx))
  let hStub1 = Handler(ctx => println(ctx))
  let hStub2 = Handler(ctx => println(ctx))
  let hStub3 = Handler(ctx => println(ctx))
  let hStub4 = Handler(ctx => println(ctx))
  let _hStub5 = Handler(ctx => println(ctx))
  let hStub6 = Handler(ctx => println(ctx))
  let hStub7 = Handler(ctx => println(ctx))
  let hStub8 = Handler(ctx => println(ctx))
  let hStub9 = Handler(ctx => println(ctx))
  let hStub10 = Handler(ctx => println(ctx))
  let hStub11 = Handler(ctx => println(ctx))
  let hStub12 = Handler(ctx => println(ctx))
  let hStub13 = Handler(ctx => println(ctx))
  let hStub14 = Handler(ctx => println(ctx))
  let hStub15 = Handler(ctx => println(ctx))
  let hStub16 = Handler(ctx => println(ctx))
  r.add(Get, "/articlefun", ctx => println(ctx), name="hStub5")
  r.add(Get, "/articles/{id}", hStub, name="hStub")
  r.add(Delete, "/articles/{slug}", hStub8, name="hStub8")
  r.add(Get, "/articles/search", hStub1, name="hStub1")
  r.add(Get, "/articles/{id}:delete", hStub8, name="hStub8")
  r.add(Get, "/articles/{iidd}!sup", hStub4, name="hStub4")
  r.add(Get, "/articles/{id}:{op}", hStub3, name="hStub3")
  r.add(Get, "/articles/{id}:{op}", hStub2, name="hStub2")
  r.add(Get, "/articles/{id}/posts/{pid}", hStub6, name="hStub6")
  r.add(
    Get,
    "/articles/{id}/posts/{month}/{day}/{year}/{slug}",
    hStub7,
    name="hStub7",
  )
  r.add(Get, "/articles/{id}.json", hStub10, name="hStub10")
  r.add(Get, "/articles/{id}/data.json", hStub11, name="hStub11")
  r.add(Get, "/articles/files/{file}.{ext}", hStub12, name="hStub12")
  r.add(Put, "/articles/me", hStub13, name="hStub13")
  r.add(Get, "/pages/*", hStub, name="hStub")
  r.add(Get, "/pages/*", hStub9, name="hStub9")
  r.add(Get, "/users/{id}", hStub14, name="hStub14")
  r.add(Get, "/users/{id}/settings/{key}", hStub15, name="hStub15")
  r.add(Get, "/users/{id}/settings/*", hStub16, name="hStub16")
  inspect(
    r.tree,
    content=(
      #|Static()
      #|    └── Static(/)
      #|        ├── Static(article)
      #|        │   ├── Static(fun) Get(/articlefun)
      #|        │   └── Static(s/)
      #|        │       ├── Static(search) Get(/articles/search)
      #|        │       ├── Static(files/)
      #|        │       │   p── Param(file,.)
      #|        │       │       └── Static(.)
      #|        │       │           p── Param(ext,/) Get(/articles/files/{file}.{ext})
      #|        │       ├── Static(me) Put(/articles/me)
      #|        │       p── Param(id,.)
      #|        │       │   └── Static(.json) Get(/articles/{id}.json)
      #|        │       p── Param(iidd,!)
      #|        │       │   └── Static(!sup) Get(/articles/{iidd}!sup)
      #|        │       p── Param(id,:)
      #|        │       │   └── Static(:)
      #|        │       │       ├── Static(delete) Get(/articles/{id}:delete)
      #|        │       │       p── Param(op,/) Get(/articles/{id}:{op})
      #|        │       p── Param(id,/) Get(/articles/{id}) Delete(/articles/{slug})
      #|        │           └── Static(/)
      #|        │               ├── Static(posts/)
      #|        │               │   p── Param(pid,/) Get(/articles/{id}/posts/{pid})
      #|        │               │       └── Static(/)
      #|        │               │           p── Param(day,/)
      #|        │               │               └── Static(/)
      #|        │               │                   p── Param(year,/)
      #|        │               │                       └── Static(/)
      #|        │               │                           p── Param(slug,/) Get(/articles/{id}/posts/{month}/{day}/{year}/{slug})
      #|        │               └── Static(data.json) Get(/articles/{id}/data.json)
      #|        ├── Static(pages/)
      #|        │   w── * Get(/pages/*)
      #|        └── Static(users/)
      #|            p── Param(id,/) Get(/users/{id})
      #|                └── Static(/settings/)
      #|                    p── Param(key,/) Get(/users/{id}/settings/{key})
      #|                    w── * Get(/users/{id}/settings/*)
      #|
    ),
  )
  let result = r.route(Get, "/articles/search")
  assert_true(
    result is RouteResult::Found(ep, _) &&
    ep.pattern == "/articles/search" &&
    ep.name == "hStub1",
  )
  let result = r.route(Get, "/articlefun")
  assert_true(
    result is RouteResult::Found(ep, _) &&
    ep.pattern == "/articlefun" &&
    ep.name == "hStub5",
  )
  let result = r.route(Get, "/articles/123")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/articles/{id}" &&
    ep.to_paramKV_array(param_values) is [ParamKV("id", "123")] &&
    ep.name == "hStub",
  )
  let result = r.route(Delete, "/articles/123mm")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/articles/{slug}" &&
    ep.to_paramKV_array(param_values) is [ParamKV("slug", "123mm")] &&
    ep.name == "hStub8",
  )
  let result = r.route(Get, "/articles/789:delete")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/articles/{id}:delete" &&
    ep.to_paramKV_array(param_values) is [ParamKV("id", "789")] &&
    ep.name == "hStub8",
  )
  let result = r.route(Get, "/articles/789!sup")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/articles/{iidd}!sup" &&
    ep.to_paramKV_array(param_values) is [ParamKV("iidd", "789")] &&
    ep.name == "hStub4",
  )
  let result = r.route(Get, "/articles/123:sync")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/articles/{id}:{op}" &&
    ep.to_paramKV_array(param_values)
    is [ParamKV("id", "123"), ParamKV("op", "sync")] &&
    ep.name == "hStub2",
  )
  let result = r.route(Get, "/articles/456/posts/1")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/articles/{id}/posts/{pid}" &&
    ep.to_paramKV_array(param_values)
    is [ParamKV("id", "456"), ParamKV("pid", "1")] &&
    ep.name == "hStub6",
  )
  let result = r.route(Get, "/articles/456/posts/09/04/1984/juice")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/articles/{id}/posts/{month}/{day}/{year}/{slug}" &&
    ep.to_paramKV_array(param_values)
    is [
      ParamKV("id", "456"),
      ParamKV("month", "09"),
      ParamKV("day", "04"),
      ParamKV("year", "1984"),
      ParamKV("slug", "juice"),
    ] &&
    ep.name == "hStub7",
  )
  let result = r.route(Get, "/articles/456.json")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/articles/{id}.json" &&
    ep.to_paramKV_array(param_values) is [ParamKV("id", "456")] &&
    ep.name == "hStub10",
  )
  let result = r.route(Get, "/articles/456/data.json")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/articles/{id}/data.json" &&
    ep.to_paramKV_array(param_values) is [ParamKV("id", "456")] &&
    ep.name == "hStub11",
  )
  let result = r.route(Get, "/articles/files/file.zip")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/articles/files/{file}.{ext}" &&
    ep.to_paramKV_array(param_values)
    is [ParamKV("file", "file"), ParamKV("ext", "zip")] &&
    ep.name == "hStub12",
  )
  let result = r.route(Get, "/articles/files/photos.tar.gz")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/articles/files/{file}.{ext}" &&
    ep.to_paramKV_array(param_values)
    is [ParamKV("file", "photos"), ParamKV("ext", "tar.gz")] &&
    ep.name == "hStub12",
  )
  let result = r.route(Put, "/articles/me")
  assert_true(
    result is RouteResult::Found(ep, _) &&
    ep.pattern == "/articles/me" &&
    ep.name == "hStub13",
  )
  let result = r.route(Get, "/articles/me")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/articles/{id}" &&
    ep.to_paramKV_array(param_values) is [ParamKV("id", "me")] &&
    ep.name == "hStub",
  )
  let result = r.route(Get, "/pages")
  assert_true(result is RouteResult::NotFound)
  let result = r.route(Get, "/pages/")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/pages/*" &&
    ep.to_paramKV_array(param_values) is [ParamKV("*", "")] &&
    ep.name == "hStub9",
  )
  let result = r.route(Get, "/pages/yes")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/pages/*" &&
    ep.to_paramKV_array(param_values) is [ParamKV("*", "yes")] &&
    ep.name == "hStub9",
  )
  let result = r.route(Get, "/users/1")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/users/{id}" &&
    ep.to_paramKV_array(param_values) is [ParamKV("id", "1")] &&
    ep.name == "hStub14",
  )
  let result = r.route(Get, "/users/")
  assert_true(result is RouteResult::NotFound)
  let result = r.route(Get, "/users/2/settings/password")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/users/{id}/settings/{key}" &&
    ep.to_paramKV_array(param_values)
    is [ParamKV("id", "2"), ParamKV("key", "password")] &&
    ep.name == "hStub15",
  )
  let result = r.route(Get, "/users/2/settings/")
  assert_true(
    result is RouteResult::Found(ep, param_values) &&
    ep.pattern == "/users/{id}/settings/*" &&
    ep.to_paramKV_array(param_values) is [ParamKV("id", "2"), ParamKV("*", "")] &&
    ep.name == "hStub16",
  )
}
