## A cassette directory on disk whose writes or deletes fail on purpose, to
## reach errors a real disk rarely gives. It is also what wrapping a
## platform's path type looks like, when one is not a `cassette_dir` as it is.
import pf.Path

FailingDir := { path : Path, failing : [Write, Delete] }.{
	join = |dir, name| FailingDir.{ path: dir.path.join(name), failing: dir.failing }
	display = |dir| dir.path.display()
	exists! = |dir| dir.path.exists!()
	read_bytes! = |dir| dir.path.read_bytes!()
	write_bytes! = |dir, bytes| if dir.failing == Write Err(DiskFull) else dir.path.write_bytes!(bytes)
	delete! = |dir| if dir.failing == Delete Err(PermissionDenied) else dir.path.delete!()
	create_all! = |dir| dir.path.create_all!()
}
