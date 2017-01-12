!
! gss: A program to compute gss[1] radial distribution functions from
!      molecular dynamics simulations in NAMD DCD format.
!
!      Important: THIS IS NOT THE CLASSICAL RADIAL DISTRIBUTION
!                 FUNCTION. It is the shape-dependent RDF used
!                 for non-spherical species. It will only coincide
!                 with the classical RDF for perfectly spherical
!                 species. The normalization of this distribution 
!                 function is more complicated than the normalization
!                 of the radial distribution function for spherical
!                 solutes. Here, we estimate the volume of the 
!                 solute* by partitioning the space into bins
!                 of side "probeside", and count how many bins contain
!                 atoms of the solute. With this estimate of the
!                 volume of the solute, the number of solvent
!                 that would be present in the simulation box for
!                 the same solvent density, but without the solute,
!                 is calculated. This number of random solvent molecules
!                 is then generated, and the gss relative to the
!                 solute for these molecules is computed for 
!                 normalization. This procedure is performed 
!                 independently for each solute structure in each
!                 frame of the trajectory.
!                 *The volume can be of a different selection than
!                  the solute selection.
!
! Please cite the following reference when using this package:
!
! I. P. de Oliveira, L. Martinez, Molecular basis of co-solvent induced
! stability of lipases. To be published. 
!
! Reference of this distribution function:
! 1. W. Song, R. Biswas and M. Maroncelli. Intermolecular interactions
! and local density augmentation in supercritical solvation: A survey of
! simulation and experimental results. Journal of Physical Chemistry A,
! 104:6924-6939, 2000.  
!
! Auxiliar dimensions:
!          memory: Controls the amount of memory used for reading dcd
!                  files. If the program ends with segmentation fault
!                  without any other printing, decrease the value of
!                  this parameter.  
!
! L. Martinez, Mar 13, 2014.
! Institute of Chemistry, State University of Campinas (UNICAMP)
!

program g_solute_solvent
 
  ! Static variables

  implicit none
  integer, parameter :: memory=15000000
  integer :: natom, nsolute, nsolvent, isolute, isolvent, &
             narg, length, firstframe, lastframe, stride, nclass,&
             nframes, dummyi, i, ntotat, memframes, ncycles, memlast,&
             j, iframe, icycle, nfrcycle, iatom, k, ii, jj, &
             status, keystatus, ndim, iargc, lastatom, nres, nrsolute,&
             nrsolvent, kframe, irad, nslabs, natoms_solvent,&
             nsmalld, ibox, jbox, kbox,&
             noccupied, nbdim(3), nboxes(3), maxsmalld, frames
  real :: gsssum, gsssum_random, gsslast, convert, gssscale
  double precision :: readsidesx, readsidesy, readsidesz, t
  real :: side(memory,3), mass1, mass2, seed,&
          cmx, cmy, cmz, beta, gamma, theta, random, axis(3)
  real, parameter :: twopi = 2.*3.1415925655
  real, parameter :: mole = 6.022140857e23
  real :: dummyr, xdcd(memory), ydcd(memory), zdcd(memory),&
          x1, y1, z1, time0, etime, tarray(2),&
          gss_norm, gss_sphere, gssstep, &
          density, dbox_x, dbox_y, dbox_z, cutoff, probeside, solute_volume,&
          totalvolume, xmin(3), xmax(3), gssmax, kbint, kbintsphere, bulkdensity
  real :: bulkdensity_average
  character(len=200) :: groupfile, line, record, value, keyword,&
                        dcdfile, inputfile, psffile, file,&
                        output
  character(len=4) :: dummyc
  logical :: readfromdcd, dcdaxis, periodic, scalelast
  real :: shellvolume, sphericalshellvolume, shellradius, dshift, sphereradiusfromshellvolume 

  ! Allocatable arrays
  
  integer, allocatable :: solute(:), solvent(:), resid(:), solute2(:), &
                          natres(:), fatres(:), fatrsolute(:), fatrsolvent(:), &
                          nrsolv(:), ismalld(:)
  real, allocatable :: gss(:)
  real, allocatable :: shellvolume_average(:), gss_average(:)
  real, allocatable :: eps(:), sig(:), q(:), e(:), s(:), mass(:),&
                       solvent_molecule(:,:), &
                       xref(:), yref(:), zref(:), xrnd(:), yrnd(:), zrnd(:),&
                       x(:), y(:), z(:), mind(:), dsmalld(:)
  character(len=6), allocatable :: class(:), segat(:), resat(:),&
                                   typeat(:), classat(:)
  logical, allocatable :: hasatoms(:,:,:)
  
  ! Compute time
  
  time0 = etime(tarray)
  
  ! Output title
  
  write(*,"(/,' ####################################################',&
            &/,/,&
            & '   GSS: Compute gss distribution from DCD files      ',&
            &/,/,&
            & ' ####################################################',/)")    
  
  call version()
  
  ! Seed for random number generator
  
  seed = 0.48154278727e0
  
  ! Some default parameters
  
  firstframe = 1
  lastframe = 0
  stride = 1
  periodic = .true.
  readfromdcd = .true.
  nslabs = 1000 
  cutoff = 10.
  gssmax = 20.
  density = 1.
  probeside = 2.
  scalelast = .false.
  
  ! Open input file and read parameters
  
  narg = iargc()
  if(narg == 0) then
    write(*,*) ' Run with: ./gss input.inp '
    stop
  end if   
  call getarg(1,record)
  
  inputfile = record(1:length(record))
  open(99,file=inputfile,action='read')
  do 
    read(99,"( a200 )",iostat=status) record
    if(status /= 0) exit
    if(keyword(record) == 'dcd') then
      dcdfile = value(record)
      write(*,*) ' DCD file name: ', dcdfile(1:length(dcdfile)) 
    else if(keyword(record) == 'groups') then
      groupfile = value(record)
      write(*,*) ' Groups file name: ', groupfile(1:length(groupfile))
    else if(keyword(record) == 'psf') then
      psffile = value(record)
      write(*,*) ' PSF file name: ', psffile(1:length(psffile))
    else if(keyword(record) == 'firstframe') then
      line = value(record)
      read(line,*,iostat=keystatus) firstframe
      if(keystatus /= 0) exit 
    else if(keyword(record) == 'lastframe') then
      line = value(record)
      if(line(1:length(line)) /= 'last') then
        read(line,*,iostat=keystatus) lastframe
      end if
      if(keystatus /= 0) exit 
    else if(keyword(record) == 'stride') then
      line = value(record)
      read(line,*,iostat=keystatus) stride
      if(keystatus /= 0) exit 
    else if(keyword(record) == 'nslabs') then
      line = value(record)
      read(line,*,iostat=keystatus) nslabs
      if(keystatus /= 0) exit 
    else if(keyword(record) == 'cutoff') then
      line = value(record)
      read(line,*,iostat=keystatus) cutoff
      if(keystatus /= 0) exit 
    else if(keyword(record) == 'gssmax') then
      line = value(record)
      read(line,*,iostat=keystatus) gssmax
      if(keystatus /= 0) exit 
    else if(keyword(record) == 'probeside') then
      line = value(record)
      read(line,*,iostat=keystatus) probeside
      if(keystatus /= 0) exit 
    else if(keyword(record) == 'density') then
      line = value(record)
      read(line,*,iostat=keystatus) density
      if(keystatus /= 0) exit 
    else if(keyword(record) == 'periodic') then
      line = value(record)
      read(line,*,iostat=keystatus) line
      if(keystatus /= 0) exit 
      if(line == 'no') then
        periodic = .false.
        readfromdcd = .false.
      else if(line == 'readfromdcd') then
        periodic = .true.
        readfromdcd = .true.
      else
        periodic = .true.
        readfromdcd = .false.
        read(record,*,iostat=keystatus) line, axis(1), axis(2), axis(3)
        if(keystatus /= 0) exit 
      end if 
    else if(keyword(record) == 'output') then
      output = value(record)
      write(*,*) ' GSS output file name: ', output(1:length(output))
    else if(keyword(record) == 'solute' .or. &
            keyword(record) == 'solvent') then
      write(*,"(a,/,a)") ' ERROR: The options solute and solvent must be used ',&
                         '        with the gss.sh script, not directly. '
      stop
    else if(keyword(record) == 'scalelast') then
      line = value(record)
      if ( trim(line) == 'yes' ) scalelast = .true.
      if ( trim(line) == 'no' ) scalelast = .false.
    else if(record(1:1) /= '#' .and. & 
            keyword(record) /= 'par' .and. &
            record(1:1) > ' ') then
      write(*,*) ' ERROR: Unrecognized keyword found: ',keyword(record)
      stop
    end if
  end do               
  close(99)
  
  ! If some error was found in some keyword value, report error and stop
  
  if(keystatus /= 0) then
    line = keyword(record)
    write(*,*) ' ERROR: Could not read value for keyword: ',line(1:length(line))
    stop
  end if
  
  ! Reading the header of psf file
  
  call getdim(psffile,inputfile,natom)
  allocate( eps(natom), sig(natom), q(natom), e(natom), s(natom), mass(natom),&
            segat(natom), resat(natom), classat(natom), typeat(natom), class(natom),&
            resid(natom), natres(natom), fatres(natom), fatrsolute(natom),&
            fatrsolvent(natom), nrsolv(natom), &
            solute2(ndim), mind(ndim) )

  ! Reading parameter files to get the vdW sigmas for the definition of exclusion
  ! zones
  
  nclass = 0
  open(99,file=inputfile,action='read',status='old')
  do while(.true.)
    read(99,"( a200 )",iostat=status) record
    if(status /= 0) exit
    if(keyword(record) == 'par') then
      file = value(record)
      write(*,*) ' Reading parameter file: ', file(1:length(file))
      call readpar(file,nclass,class,eps,sig)
    end if
  end do
  close(99)
  
  ! Allocate gss array according to nslabs

  if ( gssmax > cutoff ) then
    write(*,*) ' Warning: gssmax > cutoff, the actual gssmax will be equal to cutoff. '
    nslabs = int(cutoff/(gssmax/nslabs))
    write(*,*) '          to keep same bin precision, nlsabs = ', nslabs 
    gssmax = cutoff
  end if
  
  write(*,*) ' Number of volume slabs: ', nslabs
  allocate( gss_average(nslabs), gss(nslabs), shellvolume_average(nslabs) )

  gssstep = gssmax / float(nslabs)
         
  ! Check for simple input errors
  
  if(stride < 1) then
    write(*,*) ' ERROR: stride cannot be less than 1. ' 
    stop
  end if
  if(lastframe < firstframe.and.lastframe /= 0) then
    write(*,*) ' ERROR: lastframe must be greater or equal to firstframe. '
    stop
  end if

  ! Output some information if not set
  
  write(*,*) ' First frame to be considered: ', firstframe
  if(lastframe == 0) then
    write(*,*) ' Last frame to be considered: last '
  else
    write(*,*) ' Last frame to be considered: ', lastframe
  end if
  write(*,*) ' Stride (will jump frames): ', stride
  write(*,*) ' Cutoff for linked cells: ', cutoff
  
  ! Read PSF file
  
  write(*,*) ' Reading PSF file: ', psffile(1:length(psffile))
  call readpsf(psffile,nclass,class,eps,sig,natom,segat,resat,&
               resid,classat,typeat,q,e,s,mass,.false.)
  nres = resid(natom)
  write(*,*) ' Number of atoms in PSF file: ', natom
  write(*,*) ' Number of residues in PSF file: ', nres
  write(*,*)
  
  ! Read solute and solvent information from file
  ! First reading the size of the groups to allocate arrays

  open(10,file=groupfile,action='read')
  nsolute = 0
  nsolvent = 0
  do 
    read(10,"( a200 )",iostat=status) line
    if(status /= 0) exit
    if(line(1:4) == 'ATOM' .or. line(1:6) == 'HETATM') then 
      if(line(63:66) == '1.00') then      
        nsolute = nsolute + 1        
      end if
      if(line(63:66) == '2.00') then      
        nsolvent = nsolvent + 1        
      end if
    end if     
  end do
  if ( nsolute < 1 .or. nsolvent < 1 ) then
    write(*,*) ' ERROR: No atom selected for solute or solvent. '
    write(*,*) '        nsolute = ', nsolute
    write(*,*) '        nsolvent = ', nsolvent
    stop
  end if
  allocate ( solute(nsolute), solvent(nsolvent) )
  close(10)
  
  ! Now reading reading the group atoms
  
  open(10,file=groupfile,action='read')
  isolute = 0
  isolvent = 0
  mass1 = 0.
  mass2 = 0.
  iatom = 0
  do 
    read(10,"( a200 )",iostat=status) line
    if(status /= 0) exit
    if(line(1:4) == 'ATOM' .or. line(1:6) == 'HETATM') then 
      iatom = iatom + 1

      ! Read atoms belonging to solute

      if(line(63:66) == '1.00') then      
        isolute = isolute + 1        
        solute(isolute) = iatom
        mass1 = mass1 + mass(iatom)
      end if
  
      ! Read atoms belonging to solvent

      if(line(63:66) == '2.00') then
        isolvent = isolvent + 1        
        solvent(isolvent) = iatom
        mass2 = mass2 + mass(iatom)
      end if

    end if     
  end do
  close(10)
  lastatom = max0(solute(nsolute),solvent(nsolvent))

  ! Finding the number of atoms and the first atom of each residue
  
  j = 0
  do i = 1, natom
    if(resid(i).gt.j) then
      fatres(resid(i)) = i
      natres(resid(i)) = 1
      j = resid(i)
    else
      natres(resid(i)) = natres(resid(i)) + 1
    end if
  end do
  
  ! Counting the number of residues of the solute and solvent
  
  j = 0
  nrsolute = 0
  do i = 1, nsolute
    if(resid(solute(i)).gt.j) then
      nrsolute = nrsolute + 1 
      fatrsolute(nrsolute) = fatres(resid(solute(i)))
      j = resid(solute(i))
    end if
  end do
  j = 0
  nrsolvent = 0
  do i = 1, nsolvent
    if(resid(solvent(i)).gt.j) then
      nrsolvent = nrsolvent + 1 
      fatrsolvent(nrsolvent) = fatres(resid(solvent(i)))
      j = resid(solvent(i))
    end if
    nrsolv(i) = nrsolvent
  end do

  ! This is for the initialization of the smalldistances routine

  nrandom = 2*nrsolvent
  maxsmalld = nsolute*nrandom
  allocate( ismalld(maxsmalld), dsmalld(maxsmalld) )
  maxatom = max(nsolute+nrandom,natom)
  allocate( x(maxatom), y(maxatom), z(maxatom) )

  ! Output some group properties for testing purposes
  
  write(*,*) ' Number of atoms of solute: ', nsolute 
  write(*,*) ' First atom of solute: ', solute(1)
  write(*,*) ' Last atom of solute: ', solute(nsolute)
  write(*,*) ' Number of residues in solute: ', nrsolute
  write(*,*) ' Mass of solute: ', mass1
  write(*,*) ' Number of atoms of solvent: ', nsolvent 
  write(*,*) ' First atom of solvent: ', solvent(1)
  write(*,*) ' Last atom of solvent: ', solvent(nsolvent)
  write(*,*) ' Number of residues in solvent: ', nrsolvent
  write(*,*) ' Mass of solvent: ', mass2

  ! Check if the solvent atoms have obvious reading problems
  
  if ( mod(nsolvent,nrsolvent) /= 0 ) then
    write(*,*) ' ERROR: Incorrect count of solvent atoms or residues. '
    stop
  end if

  natoms_solvent = nsolvent / nrsolvent 
  write(*,*)  ' Number of atoms of each solvent molecule: ', natoms_solvent
  
  ! Allocate solvent molecule (this will be used to generate random coordinates
  ! for each solvent molecule, one at a time, later)
  
  allocate( solvent_molecule(natoms_solvent,3), &
            xref(natoms_solvent), yref(natoms_solvent), zref(natoms_solvent),&
            xrnd(natoms_solvent), yrnd(natoms_solvent), zrnd(natoms_solvent) )
  
  ! Checking if dcd file contains periodic cell information
  
  write(*,"( /,tr2,52('-') )")
  write(*,*) ' Periodic cell data: Read carefully. '
  call chkperiod(dcdfile,dcdaxis,readfromdcd) 
  if(.not.readfromdcd.and.periodic) then
    write(*,*) ' User provided periodic cell dimensions: '
    write(*,*) axis(1), axis(2), axis(3)
  end if
  
  ! Reading the dcd file
  
  write(*,"(tr2,52('-'),/ )")
  write(*,*) ' Reading the DCD file header: '
  open(10,file=dcdfile,action='read',form='unformatted')
  read(10) dummyc, nframes, (dummyi,i=1,8), dummyr, (dummyi,i=1,9)
  read(10) dummyi, dummyr
  read(10) ntotat
  
  write(*,*)
  write(*,*) ' Number of atoms as specified in the dcd file: ',ntotat     
  call getnframes(10,nframes,dcdaxis)
  write(*,*) ' Total number of frames in this dcd file: ', nframes
  if(nframes < lastframe) then
    write(*,*) ' ERROR: lastframe greater than the number of '
    write(*,*) '        frames of the dcd file. '
    stop
  end if
  if(lastframe == 0) lastframe = nframes    
  if(ntotat /= natom) then
    write(*,"(a,/,a)") ' ERROR: Number of atoms in the dcd file does not',&
                      &'        match the number of atoms in the psf file'
    stop
  end if
  
  ! Number of frames (used for output only)
  
  frames=(lastframe-firstframe+1)/stride
  write(*,*) ' Number of frames to read: ', frames

  ! Now going to read the dcd file
  
  memframes = memory / ntotat
  ncycles = lastframe / memframes + 1
  memlast = lastframe - memframes * ( ncycles - 1 )
  write(*,*) ' Will read and store in memory at most ', memframes,&
             ' frames per reading cycle. '
  write(*,*) ' There will be ', ncycles, ' cycles of reading. '
  write(*,*) ' Last cycle will read ', memlast,' frames. '
  write(*,*)        
  
  ! Reseting the gss distribution function
  
  do i = 1, nslabs
    gss_average(i) = 0.e0
    shellvolume_average(i) = 0.e0
  end do
  bulkdensity_average = 0.e0

  ! Initializing hasatoms array

  nbdim(1) = 1
  nbdim(2) = 1
  nbdim(3) = 1
  allocate( hasatoms(0:nbdim(1)+1,0:nbdim(2)+1,0:nbdim(3)+1))

  ! Reading dcd file and computing the gss function
   
  iframe = 0
  do icycle = 1, ncycles 
   
    write(*,"( t3,'Cycle',t10,i5,tr2,' Reading: ',f6.2,'%')",&
          advance='no') icycle, 0. 
  
    ! Each cycle fills the memory as specified by the memory parameter 
  
    if(icycle == ncycles) then
      nfrcycle = memlast
    else
      nfrcycle = memframes
    end if
  
    iatom = 0
    do kframe = 1, nfrcycle    
      if(dcdaxis) then 
        read(10) readsidesx, t, readsidesy, t, t, readsidesz
        side(kframe,1) = sngl(readsidesx)
        side(kframe,2) = sngl(readsidesy)
        side(kframe,3) = sngl(readsidesz)
      end if
      read(10) (xdcd(k), k = iatom + 1, iatom + lastatom)
      read(10) (ydcd(k), k = iatom + 1, iatom + lastatom)            
      read(10) (zdcd(k), k = iatom + 1, iatom + lastatom)           
      iatom = iatom + ntotat
      write(*,"( 7a,f6.2,'%' )",advance='no')&
           (char(8),i=1,7), 100.*float(kframe)/nfrcycle
    end do
    write(*,"(' Computing: ',f6.2,'%')",advance='no') 0.
  
    ! Computing the gss function
  
    iatom = 0
    do kframe = 1, nfrcycle
      iframe = iframe + 1

      if(mod(iframe-firstframe,stride) /= 0 .or. iframe < firstframe ) then
        iatom = iatom + ntotat
        cycle
      end if

      ! Sides of the periodic cell in this frame
  
      axis(1) = side(kframe,1) 
      axis(2) = side(kframe,2) 
      axis(3) = side(kframe,3) 

      !
      ! Computing the GSS data the simulation
      !

      do i = 1, nsolute
        ii = iatom + solute(i)
        x(solute(i)) = xdcd(ii)
        y(solute(i)) = ydcd(ii)
        z(solute(i)) = zdcd(ii)
      end do
      do i = 1, nsolvent
        ii = iatom + solvent(i)
        x(solvent(i)) = xdcd(ii)
        y(solvent(i)) = ydcd(ii)
        z(solvent(i)) = zdcd(ii)
      end do

      ! Compute all distances that are smaller than the cutoff

      call smalldistances(nsolute,solute,nsolvent,solvent,x,y,z,cutoff,&
                          nsmalld,ismalld,dsmalld,axis,maxsmalld)

      !
      ! Computing the gss functions from distance data
      !

      ! For each solvent residue, get the MINIMUM distance to the solute
    
      do i = 1, nrsolvent
        mind(i) = cutoff + 1.e0
      end do
      do i = 1, nsmalld
        isolvent = nrsolv(ismalld(i))
        if ( dsmalld(i) < mind(isolvent) ) then
          mind(isolvent) = dsmalld(i)
        end if
      end do

      ! Summing up current data to the gss histogram

      do i = 1, nslabs
        gss(i) = 0.e0
      end do
      do i = 1, nrsolvent
        irad = int(float(nslabs)*mind(i)/gssmax)+1
        if( irad <= nslabs ) then
          gss(irad) = gss(irad) + 1.e0
        end if
      end do

      !
      ! Computing volumes for normalization
      !

      do i = 1, nsolute
        ii = iatom + solute(i)
        x(i) = xdcd(ii)
        y(i) = ydcd(ii)
        z(i) = zdcd(ii)
        solute2(i) = i
      end do

      ! Generate nrandom random points

      ii = nsolute
      do i = 1, nrandom 
        ii + 1
        x(ii) = -axis(1)/2. + random(seed)*axis(1) 
        y(ii) = -axis(2)/2. + random(seed)*axis(2) 
        z(ii) = -axis(3)/2. + random(seed)*axis(3) 
        irandom(i) = ii
      end do

      ! Computes distances which are smaller than the cutoff
      
      call smalldistances(nsolute,solute2,nrandom,irandom,x,y,z,cutoff,&
                          nsmalld,ismalld,dsmalld,axis,maxsmalld)
      
      ! Estimating volume of slabs from count of random points

      do i = 1, nsmalld
        irad = int(float(nslabs)*dsmalld(i)/gssmax)+1
        if ( irad <= nslabs ) then
          random_count(irad) = random_count(irad) + 1.e0
        end if
      end do

      ! Converting counts to volume

      totalvolume = axis(1)*axis(2)*axis(3)
      do i = 1, nslabs
        shellvolume(i) = random_count(i)*totalvolume / nrandom
        shellvolume_average(i) = shellvolume_average(i) + shellvolume(i)
      end do

      ! Estimating the bulk density from site count at large distances

      gsssum = 0.e0
      totalvolume = 0.e0
      do i = ibulk, nslabs
        gsssum = gsssum + gss(i)
        totalvolume = totalvolume + shellvolume(i)
      end do
      bulkdensity = gsssum / totalvolume
      bulkdensity_average = bulkdensity_average + bulkdensity

      ! Normalizing the gss distribution at this frame
      
      do i = 1, nlsabs
        gss(i) = gss(i) / ( bulkdensity*shellvolume(i) )
        gss_average(i) = gss_average(i) + gss(i)
      end do

      ! Print progress

      write(*,"( 7a,f6.2,'%' )",advance='no')&
           (char(8),i=1,7), 100.*float(kframe)/nfrcycle
  
      iatom = iatom + ntotat
    end do
    write(*,*)
  end do
  close(10)

  ! Averaging results on the number of frames

  bulkdensity_average = bulkdensity_average / frames
  do i = 1, nslabs
    gss_average(i) = gss_average(i) / frames
    shellvolume_average(i) = shellvolume_average(i) / frames
  end do

  ! Open output file and writes all information of this run

  !
  ! GSS computed with minimum distance
  !
  
  open(20,file=output(1:length(output)))
  write(20,"( '#',/,&
             &'# Output of gss.f90: Using MINIMUM distance to solute.',/,&
             &'# Input file: ',a,/,& 
             &'# DCD file: ',a,/,& 
             &'# Group file: ',a,/,&
             &'# PSF file: ',a,/,& 
             &'# First frame: ',i5,' Last frame: ',i5,' Stride: ',i5,/,&
             &'#',/,&
             &'# Periodic boundary conditions: ',/,&
             &'# Periodic: ',l1,' Read from DCD: ',l1,/,&
             &'#',/,&
             &'# Average solute volume estimate (A^3): ',f12.5,/,&
             &'# Bulk solvent density estimated (sites/A^3): ',f12.5,/,&
             &'#',/,&
             &'# Number of atoms and mass of group 1: ',i6,f12.3,/,&
             &'# First and last atoms of group 1: ',i6,tr1,i6,/,&
             &'# Number of atoms and mass of group 2: ',i6,f12.3,/,&
             &'# First and last atoms of group 2: ',i6,tr1,i6,/,&
             &'#' )" )&
             &inputfile(1:length(inputfile)),&
             &dcdfile(1:length(dcdfile)),&
             &groupfile(1:length(groupfile)),&
             &psffile(1:length(psffile)),&
             &firstframe, lastframe, stride,&
             &periodic, readfromdcd, &
             &solute_volume, bulkdensity, &
             &nsolute, mass1, solute(1), solute(nsolute),& 
             &nsolvent, mass2, solvent(1), solvent(nsolvent)  

  ! Compute error of gssrand distribution at large distance (expected to be 1.00)

  if ( gss(nslabs) < 1.e-10 ) then
    write(*,*) ' ERROR: Something wrong with random normalization. Contact the developer. '
    stop
  end if
  gsslast = gss_random(nslabs)/gss(nslabs)
  write(20,"('# Error in random normalization at largest distance: ',f12.3,'%' )") (gsslast - 1.d0)*100

  gssscale = gss(nslabs)/shellvolume(gss_random(nslabs),bulkdensity)
  write(20,"('# Solvent density at largest distance slab (sites/A^3): ',f12.5 )") gssscale
  gssscale = gssscale / bulkdensity
  write(20,"('# Difference relative to estimated bulk density: ',f12.3,'%' )") (gssscale - 1.d0)*100
  write(20,"('#')")
  if ( scalelast ) then
    write(20,"('# scalelast is true, so GSS/GSSRND (column 2) is divided by: ',f12.3 )") gssscale
  end if
  write(20,"('#')")

  ! Output table

  write(20,"( '# COLUMNS CORRESPOND TO: ',/,&
  &'#       1  Minimum distance to solute (dmin)',/,&
  &'#       2  GSS normalized by the GSS RAND distribution. ',/,&
  &'#       3  GSS normalized according to spherical volume of radius dmin.',/,&
  &'#       4  Site count for each dmin, averaged over frames',/,&
  &'#       5  Cumulative sum of sites, averaged over the number of frames  ',/,&
  &'#       6  Site count computed from random solvent distribution, averaged over frames.',/,&
  &'#       7  Cumulative sum of sites for the random distribution, averaged over frames.',/,&
  &'#       8  Kirwood-Buff integral (cc/mol) computed from column 2 with volume estimated from col 6 (int V(r)*(gss-1) dr ',/,&
  &'#       9  Kirwood-Buff integral (cc/mol) computed from column 2 with spherical shell volume (int 4*pi*r^2*(gss-1) dr ',/,&
  &'#      10  Spherical shifted minimum distance ')")
  write(20,"( '#',/,&      
  &'#',t5,'1-DISTANCE',t24,'2-GSS',t32,'3-GSS/SPHER',t50,'4-COUNT',t64,'5-CUMUL',&
  &t74,'6-COUNT RND',t88,'7-CUMUL RND',t105,'8-KB RND',t119,'9-KB SPH',t131,'10-D SHIFT' )" )

  ! Conversion factor for KB integrals, from A^3 to cm^3/mol

  convert = mole / 1.e24

  gsssum = 0
  gsssum_random = 0
  kbint = 0.e0
  kbintsphere = 0.e0
  do i = 1, nslabs
    if ( gss_random(i) == 0 ) cycle
    gsssum = gsssum + gss(i)
    gsssum_random = gsssum_random + gss_random(i)
    ! Normalization by spherical shell of this radius
    gss_sphere = gss(i) / ( bulkdensity*sphericalshellvolume(i,gssstep) ) 
    ! Normalization by random distribution of molecules
    if ( gss_random(i) > 0. ) then
      gss_norm = gss(i) / gss_random(i)
    else
      gss_norm = 0.
    end if
    dshift = sphereradiusfromshellvolume(gss_random(i)/bulkdensity,gssstep)
    if ( scalelast ) gss_norm = gss_norm / gssscale
    kbint = kbint + convert*(gss_norm - 1.e0)*shellvolume(gss_random(i),bulkdensity)
    kbintsphere = kbintsphere + convert*(gss_norm - 1.e0)*sphericalshellvolume(i,gssstep)
    write(20,"( 10(tr2,f12.7) )")&
    shellradius(i,gssstep), gss_norm, gss_sphere, gss(i), gsssum, gss_random(i), gsssum_random,&
                            kbint, kbintsphere, dshift
  end do
  close(20)

  ! Write final messages with names of output files and their content
  
  time0 = etime(tarray) - time0
  write(*,*)
  write(*,"( tr2,52('-') )")
  write(*,*)
  write(*,*) ' OUTPUT FILES: ' 
  write(*,*)
  write(*,*) ' Wrote GSS output file: ', output(1:length(output))
  write(*,*)
  write(*,*) ' Which contains the volume-normalized and'
  write(*,*) ' unnormalized gss functions. '
  write(*,*) 
  write(*,*) ' Running time: ', time0
  write(*,*) '####################################################'
  write(*,*) 
  write(*,*) '  END: Normal termination.  '
  write(*,*) 
  write(*,*) '####################################################'
  write(*,*)        

end program g_solute_solvent

! Computes the volume of the shell given the random distribution
! count and the average bulk density

real function shellvolume(gss_random,bulkdensity)

  implicit none
  real :: gss_random, bulkdensity

  shellvolume = gss_random / bulkdensity

end function shellvolume

! Computes the volume of the spherical shell 
! defined within [(i-1)*step,i*step]

real function sphericalshellvolume(i,step)

  implicit none
  integer :: i
  real :: step, rmin
  real, parameter :: fourthirdsofpi = (4./3.)*3.1415925655

  rmin = (i-1)*step
  sphericalshellvolume = fourthirdsofpi*( (rmin+step)**3 - rmin**3 )

end function sphericalshellvolume

! Compute the point in which the radius comprises half of the
! volume of the shell

real function shellradius(i,step)

  implicit none
  integer :: i
  real :: step, rmin

  rmin = (i-1)*step
  shellradius = ( 0.5e0*( (rmin+step)**3 + rmin**3 ) )**(1.e0/3.e0)

end function shellradius

! Computes the radius that corresponds to a spherical shell of
! a given volume

real function  sphereradiusfromshellvolume(volume,step)
 
  implicit none
  real :: volume, step, rmin
  real, parameter :: pi = 3.1415925655
  real, parameter :: fourthirdsofpi = (4./3.)*3.1415925655
  
  rmin = (sqrt(3*pi)*sqrt(3*step*volume-pi*step**4)-3*pi*step**2)/(6*pi*step)
  sphereradiusfromshellvolume = ( 0.5e0*( volume/fourthirdsofpi + 2*rmin**3 ) )**(1.e0/3.e0)

end function sphereradiusfromshellvolume










