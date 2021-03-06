!
! smalldistances: This routine that returns a list of the distances 
!                 between atoms that are smaller than a specified cutoff,
!                 for a given set of coordinates.
!
! L. Martinez, Sep 23, 2014.
!
! On input: 
!    ngroup1: Number of atoms of group1 (solute)
!    group1: Vector containing the indexes in vectors x,y,z of the atoms of group1
!    ngroup2: Number of atoms of group2 (solvent) 
!    group2: Vector containing the indexes in vectors x,y,z of the atoms of group2
!    x,y,z: Coordinates of the atoms x(group1(1)), for example, is the first atom of group1
!    cutoff: The maximum distance to be considered
!    axisin: vector of dimension 3 containing the size of the periodic box in each dimension
!    maxsmalld: The estimated maximum number of distances that will be computed (see memerror)
!
! On output:
!    nsmalld: Number of distances between atoms of group1 and group1 which are smaller than 'cutoff'
!    ismalld: Indexes of the atoms of group1 and group2 corresponding to the distance reported in vector dsmalld
!             Note: the indexes go from 1 to ngroup1 and from 1 to ngroup2
!    dsmalld: The actual distance of atom of group2 to some atom of group1 (here we do not care
!             about the identity of the solute atom).
!
!    memerror: On output, it is true if the number of distances computed is greater than
!              maxsmalld. The number of distances will be stored in nsmalld, but ismalld and
!              dsmalld will not contain relevant data. If memerror is true, these two
!              vectors must be reallocated with at least "nsmalld" positions and the 
!              routine should be called again. 
!

module smalldistances_linkedcells

  integer, allocatable :: iatomfirst(:,:,:), iatomnext(:)
  integer :: nboxes(3)
  real :: cutoff2, axis(3)

end module smalldistances_linkedcells

subroutine smalldistances(ngroup1,group1,ngroup2,group2,x,y,z,cutoff,&
                          nsmalld,ismalld,dsmalld,axisin,maxsmalld,memerror)

  use smalldistances_linkedcells
  implicit none
  integer :: i, j, k, ngroup1, ngroup2, nsmalld, ibox, jbox, kbox, igroup1, ii
  integer, allocatable :: group1_box(:,:)
  integer :: group1(*), group2(*), nbdim(3)
  real :: x(*), y(*), z(*), x1, y1, z1, axisin(3)
  real :: cutoff, xmin(3), xmax(3), boxlength, dbox_x, dbox_y, dbox_z

  ! Large arrays

  logical :: memerror
  integer :: maxsmalld
  integer :: ismalld(maxsmalld,2)
  real :: dsmalld(maxsmalld)

  ! Get the axis of the periodic cell 

  axis(1) = axisin(1)
  axis(2) = axisin(2)
  axis(3) = axisin(3)

  ! Number of cells of linked cell method in each direction (initialization)
  
  do i = 1, 3
    nbdim(i) = 0
  end do
  allocate( iatomfirst(1,1,1), iatomnext(ngroup2), group1_box(ngroup1,3) )
  cutoff2 = cutoff**2

  ! Putting the atoms in their minimum image coordinates 

  do i = 1, ngroup1
    x1 = x(group1(i))
    y1 = y(group1(i))
    z1 = z(group1(i))
    call image(x1,y1,z1,axis(1),axis(2),axis(3))
    x(group1(i)) = x1
    y(group1(i)) = y1
    z(group1(i)) = z1
  end do
  do i = 1, ngroup2
    x1 = x(group2(i))
    y1 = y(group2(i))
    z1 = z(group2(i))
    call image(x1,y1,z1,axis(1),axis(2),axis(3))
    x(group2(i)) = x1
    y(group2(i)) = y1
    z(group2(i)) = z1
  end do

  ! Prepare the linked cells
  
  xmin(1) = -axis(1) / 2.
  xmin(2) = -axis(2) / 2.
  xmin(3) = -axis(3) / 2.
  xmax(1) = axis(1) / 2.
  xmax(2) = axis(2) / 2.
  xmax(3) = axis(3) / 2.

  ! The side of the linked cells must be an exact divisor of the
  ! box side, because of the phantom replicas 
 
  boxlength = xmax(1) - xmin(1) 
  nboxes(1) = max(1,int(boxlength/cutoff))
  dbox_x = boxlength / nboxes(1)

  boxlength = xmax(2) - xmin(2) 
  nboxes(2) = max(1,int(boxlength/cutoff))
  dbox_y = boxlength / nboxes(2)

  boxlength = xmax(3) - xmin(3) 
  nboxes(3) = max(1,int(boxlength/cutoff))
  dbox_z = boxlength / nboxes(3)

  ! If the number of cells increased from the previous frame, update dimensions

  if ( nboxes(1) > nbdim(1) .or. &
       nboxes(2) > nbdim(2) .or. &
       nboxes(3) > nbdim(3) ) then
    deallocate( iatomfirst )
    nbdim(1) = nboxes(1)
    nbdim(2) = nboxes(2)
    nbdim(3) = nboxes(3)
    allocate( iatomfirst(0:nbdim(1)+1,0:nbdim(2)+1,0:nbdim(3)+1) )
  end if

  ! Reseting the iatomfirst array
  
  do i = 0, nboxes(1) + 1
    do j = 0, nboxes(2) + 1
      do k = 0, nboxes(3) + 1
        iatomfirst(i,j,k) = 0
      end do
    end do
  end do

  ! Putting the atoms in their boxes
  
  do i = 1, ngroup1
    ibox = int( (x(group1(i)) - xmin(1)) / dbox_x ) + 1
    jbox = int( (y(group1(i)) - xmin(2)) / dbox_y ) + 1
    kbox = int( (z(group1(i)) - xmin(3)) / dbox_z ) + 1
    if ( ibox == nbdim(1)+1 ) ibox = nbdim(1)
    if ( jbox == nbdim(2)+1 ) jbox = nbdim(2)
    if ( kbox == nbdim(3)+1 ) kbox = nbdim(3)
    group1_box(i,1) = ibox
    group1_box(i,2) = jbox
    group1_box(i,3) = kbox
  end do
  do i = 1, ngroup2
    ibox = int( (x(group2(i)) - xmin(1)) / dbox_x ) + 1
    jbox = int( (y(group2(i)) - xmin(2)) / dbox_y ) + 1
    kbox = int( (z(group2(i)) - xmin(3)) / dbox_z ) + 1
    if ( ibox == nbdim(1)+1 ) ibox = nbdim(1)
    if ( jbox == nbdim(2)+1 ) jbox = nbdim(2)
    if ( kbox == nbdim(3)+1 ) kbox = nbdim(3)
    iatomnext(i) = iatomfirst(ibox,jbox,kbox)
    iatomfirst(ibox,jbox,kbox) = i
  end do

  ! Filling up boundaries of periodic cell with phantom copies of the solvent atoms

  call phantomcells(nboxes,iatomfirst,nbdim)

  !
  ! The linked cell lists are ready, now computing the distances
  !

  ! Loop over group1 atoms

  nsmalld = 0
  do igroup1 = 1, ngroup1
  
    ii = group1(igroup1)
    i = group1_box(igroup1,1)  
    j = group1_box(igroup1,2)  
    k = group1_box(igroup1,3)  

    ! Check on the adjacent boxes if there is an atom of the solvent which is close enough
  
    ! Inside box
  
    call smalldcell(x,y,z,ii,igroup1,group2,i,j,k,nsmalld,ismalld,dsmalld,maxsmalld,memerror)
  
    ! Interactions of boxes that share faces
  
    call smalldcell(x,y,z,ii,igroup1,group2,i+1,j,k,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
    call smalldcell(x,y,z,ii,igroup1,group2,i,j+1,k,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
    call smalldcell(x,y,z,ii,igroup1,group2,i,j,k+1,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
  
    call smalldcell(x,y,z,ii,igroup1,group2,i-1,j,k,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
    call smalldcell(x,y,z,ii,igroup1,group2,i,j-1,k,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
    call smalldcell(x,y,z,ii,igroup1,group2,i,j,k-1,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
  
    ! Interactions of boxes that share axes
  
    call smalldcell(x,y,z,ii,igroup1,group2,i+1,j+1,k,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
    call smalldcell(x,y,z,ii,igroup1,group2,i+1,j,k+1,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
    call smalldcell(x,y,z,ii,igroup1,group2,i+1,j-1,k,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
    call smalldcell(x,y,z,ii,igroup1,group2,i+1,j,k-1,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
  
    call smalldcell(x,y,z,ii,igroup1,group2,i,j+1,k+1,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
    call smalldcell(x,y,z,ii,igroup1,group2,i,j+1,k-1,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
    call smalldcell(x,y,z,ii,igroup1,group2,i,j-1,k+1,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
    call smalldcell(x,y,z,ii,igroup1,group2,i,j-1,k-1,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
  
    call smalldcell(x,y,z,ii,igroup1,group2,i-1,j+1,k,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
    call smalldcell(x,y,z,ii,igroup1,group2,i-1,j,k+1,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
    call smalldcell(x,y,z,ii,igroup1,group2,i-1,j-1,k,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
    call smalldcell(x,y,z,ii,igroup1,group2,i-1,j,k-1,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
  
    ! Interactions of boxes that share vertices
  
    call smalldcell(x,y,z,ii,igroup1,group2,i+1,j+1,k+1,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
    call smalldcell(x,y,z,ii,igroup1,group2,i+1,j+1,k-1,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
    call smalldcell(x,y,z,ii,igroup1,group2,i+1,j-1,k+1,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
    call smalldcell(x,y,z,ii,igroup1,group2,i+1,j-1,k-1,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
  
    call smalldcell(x,y,z,ii,igroup1,group2,i-1,j+1,k+1,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
    call smalldcell(x,y,z,ii,igroup1,group2,i-1,j+1,k-1,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
    call smalldcell(x,y,z,ii,igroup1,group2,i-1,j-1,k+1,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 
    call smalldcell(x,y,z,ii,igroup1,group2,i-1,j-1,k-1,nsmalld,ismalld,dsmalld,maxsmalld,memerror) 

  end do
  deallocate( iatomfirst, iatomnext, group1_box )

  return
end subroutine smalldistances

!
! Subroutine that checks the distance crterium and build the list of distances
! smaller than the cutoff
!

subroutine smalldcell(x,y,z,ii,igroup1,group2,ibox,jbox,kbox,&
                      nsmalld,ismalld,dsmalld,maxsmalld,memerror)  

   use smalldistances_linkedcells
   implicit none
   real :: d2, x1, y1, z1, x(*), y(*), z(*)
   integer :: nsmalld, ii, igroup1, igroup2, ibox, jbox, kbox,&
              group2(*), jj

   ! For large arrays
  
   logical :: memerror
   integer :: maxsmalld
   integer :: ismalld(maxsmalld,2)
   real :: dsmalld(maxsmalld)

   igroup2 = iatomfirst(ibox,jbox,kbox)
   do while( igroup2 /= 0 )
     jj = group2(igroup2)

     if ( ii == jj ) then
       igroup2 = iatomnext(igroup2) 
       cycle
     end if

     call movephantomcoor(x(jj),y(jj),z(jj),x1,y1,z1,nboxes,ibox,jbox,kbox,axis)

     d2 = ( x(ii) - x1 )**2 + &
          ( y(ii) - y1 )**2 + &
          ( z(ii) - z1 )**2

     if ( d2 < cutoff2 ) then
       nsmalld = nsmalld + 1
       if ( nsmalld > maxsmalld ) then
         memerror = .true.
       else
         ismalld(nsmalld,1) = igroup1
         ismalld(nsmalld,2) = igroup2
         dsmalld(nsmalld) = sqrt(d2)
       end if
     end if

     igroup2 = iatomnext(igroup2)
   end do

end subroutine smalldcell

