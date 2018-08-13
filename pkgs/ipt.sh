# ================================================================
# Compile Intel Processor Trace decoder library
# ================================================================

[ -e $STAGE/ipt ] && ( set -xe
    cd $SCRATCH
    
    # ------------------------------------------------------------

    until git clone --depth 1 --single-branch -b "$(git ls-remote --tags "$GIT_MIRROR/01org/processor-trace.git" | sed -n 's/.*[[:space:]]refs\/tags\/\(v[0-9\.]*\)[[:space:]]*$/\1/p' | sort -V | tail -n1)" "$GIT_MIRROR/01org/processor-trace.git" ipt; do echo 'Retrying'; done
    cd ipt

    # ------------------------------------------------------------

    . "$ROOT_DIR/pkgs/utils/fpm/pre_build.sh"

    (
        set +xe
        . scl_source enable devtoolset-7
        set -xe

        mkdir -p build
        cd $_

        # TODO: Enable test once the gtest linking issue is fixed (already in PR)
        cmake                                       \
            -DCMAKE_BUILD_TYPE=Release              \
            -DCMAKE_C{,XX}_COMPILER_LAUNCHER=ccache \
            -DCMAKE_C{,XX}_FLAGS="-g"               \
            -DCMAKE_INSTALL_PREFIX="$INSTALL_ABS"   \
            -DSIDEBAND=ON                           \
            -DFEATURE_ELF=ON                        \
            -DMAN=ON                                \
            -DPEVENT=ON                             \
            -DPTDUMP=ON                             \
            -DPTTC=ON                               \
            -DPTUNIT=ON                             \
            -DPTXED=OFF                             \
            -G"Ninja"                               \
            ..

        time cmake --build .
        time cmake --build . --target test
        time cmake --build . --target install
    )

    "$ROOT_DIR/pkgs/utils/fpm/install_from_git.sh"

    # ------------------------------------------------------------

    cd
    rm -rf $SCRATCH/ipt
)
sudo rm -vf $STAGE/ipt
sync || true