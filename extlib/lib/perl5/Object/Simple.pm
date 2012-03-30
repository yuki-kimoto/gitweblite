package Object::Simple;

our $VERSION = '3.0625';

use strict;
use warnings;
no warnings 'redefine';

use Carp ;

sub import {
    my ($class, @methods) = @_;

    # Caller
    my $caller = caller;
    
    # Base
    if ((my $flag = $methods[0] || '') eq '-base') {

        # Can haz?
        no strict 'refs';
        no warnings 'redefine';
        *{"${caller}::has"} = sub { attr($caller, @_) };
        
        # Inheritance
        if (my $module = $methods[1]) {
            $module =~ s/::|'/\//g;
            require "$module.pm" unless $module->can('new');
            push @{"${caller}::ISA"}, $module;
        }
        else {
            push @{"${caller}::ISA"}, $class;
        }

        # strict!
        strict->import;
        warnings->import;

        # Modern!
        feature->import(':5.10') if $] >= 5.010;        
    }
    # Method export
    else {
        
        # Exports
        my %exports = map { $_ => 1 } qw/new attr class_attr dual_attr/;
        
        # Export methods
        foreach my $method (@methods) {
            
            # Can be Exported?
            Carp::croak("Cannot export '$method'.")
              unless $exports{$method};
            
            # Export
            no strict 'refs';
            *{"${caller}::$method"} = \&{"$method"};
        }
    }
}

sub new {
  my $class = shift;
  bless @_ ? @_ > 1 ? {@_} : {%{$_[0]}} : {}, ref $class || $class;
}

sub attr {
    my ($self, @args) = @_;
    
    my $class = ref $self || $self;
    
    # Fix argument
    unshift @args, (shift @args, undef) if @args % 2;
    
    for (my $i = 0; $i < @args; $i += 2) {
        
        # Attribute name
        my $attrs = $args[$i];
        $attrs = [$attrs] unless ref $attrs eq 'ARRAY';
        
        # Default
        my $default = $args[$i + 1];
        
        foreach my $attr (@$attrs) {

            Carp::croak("Default value of attr must be string or number " . 
                        "or code reference (${class}::$attr)")
              unless !ref $default || ref $default eq 'CODE';

        # Code
        my $code;
        if (defined $default && ref $default) {



$code = sub {
    if(@_ == 1) {
        return $_[0]->{$attr} = $default->($_[0]) unless exists $_[0]->{$attr};
        return $_[0]->{$attr};
    }
    $_[0]->{$attr} = $_[1];
    $_[0];
}

        }
        elsif (defined $default && ! ref $default) {



$code = sub {
    if(@_ == 1) {
        return $_[0]->{$attr} = $default unless exists $_[0]->{$attr};
        return $_[0]->{$attr};
    }
    $_[0]->{$attr} = $_[1];
    $_[0];
}



    }
    else {



$code = sub {
    return $_[0]->{$attr} if @_ == 1;
    $_[0]->{$attr} = $_[1];
    $_[0];
}



    }
            
            no strict 'refs';
            *{"${class}::$attr"} = $code;
        }
    }
}


# DEPRECATED!
sub class_attr {
    require Object::Simple::Accessor;
    Object::Simple::Accessor::create_accessors('class_attr', @_)
}

# DEPRECATED!
sub dual_attr {
    require Object::Simple::Accessor;
    Object::Simple::Accessor::create_accessors('dual_attr',  @_)
}

=head1 NAME

Object::Simple - Create attribute method, and provide constructor

=head1 SYNOPSIS

    package SomeClass;
    use Object::Simple -base;
    
    # Create a attribute method
    has 'foo';
    
    # Create a attribute method having default value
    has foo => 1;
    has foo => sub { [] };
    has foo => sub { {} };
    has foo => sub { OtherClass->new };
    
    # Create attribute methods at once
    has [qw/foo bar baz/];
    has [qw/foo bar baz/] => 0;
    
    # Create all attribute methods at once
    has [qw/foo bar baz/],
        some => 1,
        other => sub { 5 };

Use the class.

    # Create a new object
    my $obj = SomeClass->new;
    my $obj = SomeClass->new(foo => 1, bar => 2);
    my $obj = SomeClass->new({foo => 1, bar => 2});
    
    # Get and set a attribute value
    my $foo = $obj->foo;
    $obj->foo(1);

Inheritance

    package Foo;
    use Object::Simple -base;
    
    package Bar;
    use Foo -base;
    # or use Object::Simple -base => 'Foo';

=head1 DESCRIPTION

L<Object::Simple> is a generator of attribute method,
such as L<Class::Accessor>, L<Mojo::Base>, or L<Moose>.
L<Class::Accessor> is simple, but lack offten used features.
C<new> method can't receive hash arguments.
Default value can't be specified.
If multipule values is set through the attribute method,
its value is converted to array reference without warnings.

Some people find L<Moose> too complex, and dislike that 
it depends on outside modules. Some say that L<Moose> is 
almost like another language and does not fit the familiar 
perl syntax. In some cases, in particular smaller projects, 
some people feel that L<Moose> will increase complexity
and therefore decrease programmer efficiency.
In addition, L<Moose> can be slow at compile-time and 
its memory usage can get large.

L<Object::Simple> is the middle way between L<Class::Accessor>
and complex class builder. Only offten used features is
implemented. L<Object::Simple> is similar with L<Mojo::Base>.
C<new> can receive hash or hash reference as arguments.
You can specify default value for the attribute.
Compile speed is fast and used memory is small.

=head1 GUIDE

See L<Object::Simple::Guide> to know L<Object::Simple> details.

=head1 FUNCTIONS

If you specify -base flag, you can inherit Object::Simple
and import C<has> function.
C<has> function create attribute method.

    package Foo;
    use Object::Simple -base;
    
    has x => 1;
    has y => 2;

strict and warnings is automatically enabled and 
Perl 5.10 features is imported.

You can use C<-base> flag in sub class for inheritance.

    package Bar;
    use Foo -base;
    # or use Object::Simple -base => 'Foo';
    
    has z => 3;

This is equal to

    package Bar;
    
    use base 'Foo';
    use strict;
    use warnings;
    use feature ':5.10';
    sub has { __PACKAGE__->attr(@_) }
    
=head2 C<has>

Create attribute method.
    
    has 'foo';
    has [qw/foo bar baz/];
    has foo => 1;
    has foo => sub { {} };

Create attribute method. C<has> receive
attribute name and default value.
Default value is optional.
If you want to create multipule attribute methods at once,
specify attribute names as array reference at first argument.

If you want to specify reference or object as default value,
it must be code reference
not to share the value with other objects.

Get and set a attribute value.

    my $foo = $obj->foo;
    $obj->foo(1);

If a default value is specified and the value is not exists,
you can get default value.

If a value is set, the attribute return self object.
So you can set a value repeatedly.

   $obj->foo(1)->bar(2);

You can create all attribute methods at once.

    has [qw/foo bar baz/],
        pot => 1,
        mer => sub { 5 };

=head1 METHODS

=head2 C<new>

    my $obj = Object::Simple->new(foo => 1, bar => 2);
    my $obj = Object::Simple->new({foo => 1, bar => 2});

Create a new object. C<new> receive
hash or hash reference as arguments.

=head2 C<attr>

    __PACKAGE__->attr('foo');
    __PACKAGE__->attr([qw/foo bar baz/]);
    __PACKAGE__->attr(foo => 1);
    __PACKAGE__->attr(foo => sub { {} });

    __PACKAGE__->attr(
        [qw/foo bar baz/],
        pot => 1,
        mer => sub { 5 }
    );

Create attribute.
C<attr> method usage is equal to C<has> method.

=head1 DEPRECATED FUNCTIONALITY

    class_attr method # will be removed 2017/1/1
    dual_attr method # will be removed 2017/1/1

=head1 BACKWARDS COMPATIBILITY POLICY

If a functionality is DEPRECATED, you can know it by DEPRECATED warnings
except for attribute method.
You can check all DEPRECATED functionalities by document.
DEPRECATED functionality is removed after five years,
but if at least one person use the functionality and tell me that thing
I extend one year each time he tell me it.

EXPERIMENTAL functionality will be changed without warnings.

(This policy was changed at 2011/10/22)

=head1 BUGS

Tell me the bugs
by mail or github L<http://github.com/yuki-kimoto/Object-Simple>

=head1 AUTHOR
 
Yuki Kimoto, C<< <kimoto.yuki at gmail.com> >>
 
=head1 COPYRIGHT & LICENSE
 
Copyright 2008 Yuki Kimoto, all rights reserved.
 
This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
 
=cut
 
1;

