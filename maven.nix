{ pkgs, lib }:
let
  localRepoArg = location: ''-Dmaven.repo.local="${location}"'';
  localDependencyFolder = { groupId, artifactId, version, ... }: "${builtins.replaceStrings ["."] ["/"] groupId}/${artifactId}/${version}";
  # https://maven.apache.org/repositories/layout.html
  artifactName = { artifactId, version, ... }: "${artifactId}-${version}.jar";

  mavenDependencyPlugin = pkgs.stdenv.mkDerivation rec {
    groupId = "org.apache.maven.plugins";
    artifactId = "maven-dependency-plugin";
    version = "3.6.0";
    name = artifactId;

    nativeBuildInputs = [ pkgs.maven ];

    builder = pkgs.writeShellScript "builder.sh" ''
      source $stdenv/setup

      mvn ${groupId}:${artifactId}:${version}:get -DgroupId=${groupId} -DartifactId=${artifactId} -Dversion=${version} ${localRepoArg "$out"}
      # Contain timestamps
      shopt -s globstar
      rm $out/**/_remote.repositories
    '';

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-1mhIBThC+MDZCkvQBIGBnl8IxT9sq7lZRoxSMH5AFZQ=";

    # https://nixos.org/manual/nix/stable/language/advanced-attributes.html#adv-attr-preferLocalBuild
    preferLocalBuild = true;
  };
in
rec {
  inherit mavenDependencyPlugin;

  mavenDependency = lib.makeOverridable (
    { groupId, artifactId, version, hash }@args:
    pkgs.stdenv.mkDerivation {
      name = "maven-dependency-${groupId}:${artifactId}:${version}";
      builder = pkgs.writeShellScript "builder.sh" ''
        source $stdenv/setup

        # Set up maven dependency plugin
        mkdir helper
        cp -r "${mavenDependencyPlugin}"/* helper
        # Make them writable, maven likes to touch them
        chmod -R +w helper

        mvn dependency:get -DgroupId=${groupId} -DartifactId=${artifactId} -Dversion=${version} -Dtransitive=false ${localRepoArg "helper"}

        cp helper/${localDependencyFolder args}/*.jar $out
        rm -rf helper
      '';
      nativeBuildInputs = [ pkgs.maven ];

      outputHashAlgo = "sha256";
      outputHashMode = "flat";
      outputHash = hash;

      meta = { inherit groupId artifactId version; };

      # https://nixos.org/manual/nix/stable/language/advanced-attributes.html#adv-attr-preferLocalBuild
      preferLocalBuild = true;
    }
  );

  dependenciesFromLockfile = lockfileJson:
    let
      findDependenciesRecursive = json:
        [{ inherit (json) groupId artifactId version; hash = json.checksum; }]
        ++ builtins.concatMap findDependenciesRecursive json.children;
    in
    lib.unique (builtins.concatMap findDependenciesRecursive lockfileJson.dependencies);

  repoForDependencies = dependencies:
    let
      createPackageDirectory = package: "mkdir -p $out/${localDependencyFolder package.meta}";
      copyPackageFile = package:
        let folder = localDependencyFolder package.meta; in
        ''
          mkdir -p $out/${folder}
          cp "${package}" $out/${folder}/${artifactName package.meta}
        '';
    in
    pkgs.stdenv.mkDerivation rec {
      name = "maven-repository";

      builder = pkgs.writeShellScript "builder.sh" ''
        source $stdenv/setup
        mkdir $out

        ${lib.concatLines (builtins.map createPackageDirectory dependencies)}
        ${lib.concatLines (builtins.map copyPackageFile dependencies)}
      '';

      # https://nixos.org/manual/nix/stable/language/advanced-attributes.html#adv-attr-preferLocalBuild
      preferLocalBuild = true;
    };

  buildMaven = { name, version, src, lockfile }:
    let
      depsAsJson = dependenciesFromLockfile (lib.importJSON lockfile);
      depsAsDerivation = builtins.map mavenDependency depsAsJson;
      repository = repoForDependencies depsAsDerivation;
    in
    pkgs.stdenv.mkDerivation rec {
      inherit name version;
      inherit src;

      buildPhase = ''
        mvn --offline package ${localRepoArg repository}
      '';

      installPhase = ''
        mkdir $out

        cp -r target $out
      '';

      nativeBuildInputs = [ pkgs.maven ];
    };

}
