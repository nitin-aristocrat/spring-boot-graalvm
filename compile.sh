#!/usr/bin/env bash

if [ -z "$1" ];
  then
    echo "[--> ERROR] Please provide your Spring Boot Main class as script parameter like this: ./compile.sh your.package.YourSpringBootApplicationClass"
    exit
fi
echo "[-->] Using Mainclass '$1' provided as parameter"
MAINCLASS=$1

echo "[-->] Detect artifactId from pom.xml"
ARTIFACT=$(mvn -q \
-Dexec.executable=echo \
-Dexec.args='${project.artifactId}' \
--non-recursive \
exec:exec);
echo "artifactId is '$ARTIFACT'"

echo "[-->] Detect artifact version from pom.xml"
VERSION=$(mvn -q \
  -Dexec.executable=echo \
  -Dexec.args='${project.version}' \
  --non-recursive \
  exec:exec);
echo "artifact version is $VERSION"

echo "[-->] Cleaning target directory & creating new one"
rm -rf target
mkdir -p target/native-image

echo "[-->] Build Spring Boot App with mvn package"
mvn -DskipTests package

echo "[-->] Expanding the Spring Boot fat jar"
JAR="$ARTIFACT-$VERSION.jar"
cd target/native-image
jar -xvf ../$JAR >/dev/null 2>&1
cp -R META-INF BOOT-INF/classes

echo "[-->] Set the classpath to the contents of the fat jar & add the Spring Graal AutomaticFeature to the classpath"
LIBPATH=`find BOOT-INF/lib | tr '\n' ':'`
MAVEN_REPO_HOME=~/.m2/repository
FEATURE=$MAVEN_REPO_HOME/org/springframework/experimental/spring-graal-native/0.6.1.RELEASE/spring-graal-native-0.6.1.RELEASE.jar
CP=BOOT-INF/classes:$LIBPATH:$FEATURE

GRAALVM_VERSION=`native-image --version`
echo "[-->] Compiling Spring Boot App '$ARTIFACT' with $GRAALVM_VERSION"
time native-image \
  --no-server \
  --no-fallback \
  --initialize-at-build-time=io.netty.util.NetUtil,io.netty.util.AbstractReferenceCounted,io.netty.channel.DefaultFileRegion \
  -H:+TraceClassInitialization \
  -H:Name=$ARTIFACT \
  -H:+ReportExceptionStackTraces \
  -Dspring.graal.remove-unused-autoconfig=true \
  -Dspring.graal.remove-yaml-support=true \
  -cp $CP $MAINCLASS;

# Since GraalVM 19.0, application classes in native images are by default initialized at run time and no longer at image build time.
# see https://medium.com/graalvm/updates-on-class-initialization-in-graalvm-native-image-generation-c61faca461f7
# so --initialize-at-build-time \ should'nt be needed anymore