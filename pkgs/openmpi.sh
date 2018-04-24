# ================================================================
# OpenMPI
# ================================================================

[ -e $STAGE/ompi ] && ( set -xe
    cd $SCRATCH

    until git clone --depth 1 --no-checkout --no-single-branch $GIT_MIRROR/open-mpi/ompi.git; do echo 'Retrying'; done
    cd ompi
    git checkout $(git tag | sed -n '/^v[0-9\.]*$/p' | sort -V | tail -n1)

    # ------------------------------------------------------------

    . "$ROOT_DIR/pkgs/utils/fpm/pre_build.sh"

    (
        set +xe
        . scl_source enable devtoolset-6
        set -xe

        ./autogen.pl
        ./configure                             \
            --enable-mpi-cxx                    \
            --enable-mpi-ext                    \
            --enable-mpi-java                   \
            --enable-mpirun-prefix-by-default   \
            --enable-sparse-groups              \
            --enable-static                     \
            --prefix="$INSTALL_ABS/openmpi"     \
            --with-cuda                         \
            --with-sge                          \
            --with-slurm

        make -j$(nproc)
        make -j install
    )

    "$ROOT_DIR/pkgs/utils/fpm/install_from_git.sh"
    
    # ------------------------------------------------------------

    cd
    rm -rf $SCRATCH/ompi
)
sudo rm -vf $STAGE/ompi
sync || true
