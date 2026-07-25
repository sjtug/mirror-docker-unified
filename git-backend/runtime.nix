{
  buildEnv,
  fcgiwrap,
  gitMinimal,
  goQueue,
  multiwatch,
  nginx,
  spawn_fcgi,
  tini,
}:

buildEnv {
  name = "git-backend-runtime";
  paths = [
    fcgiwrap
    gitMinimal
    goQueue
    multiwatch
    nginx
    spawn_fcgi
    tini
  ];
}
